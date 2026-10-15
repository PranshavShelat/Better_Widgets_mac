import CoreLocation
import Foundation
import Observation

/// Weather from Open-Meteo (free, no API key).
@Observable
@MainActor
final class WeatherService {
    enum Status: Equatable {
        case needsCity, loading, ready
        case failed(String)
    }

    struct Current {
        var temperature: Double
        var apparent: Double
        var humidity: Double
        var wind: Double
        var code: Int
        var isDay: Bool
    }

    struct Hour: Identifiable {
        let id: String
        let date: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
    }

    struct Day: Identifiable {
        let id: String
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let precipitation: Int?
    }

    var status: Status = .needsCity
    var locationName = ""
    var current: Current?
    var hours: [Hour] = []
    var days: [Day] = []
    var sunrise: Date?
    var sunset: Date?
    var timeZone = TimeZone.current
    var unit: TemperatureUnit = .celsius
    var updatedAt: Date?

    @ObservationIgnored weak var settings: WidgetSettings?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let locator = LocationProvider()
    @ObservationIgnored private var currentPlace: Place?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        Task { await load() }
    }

    private func load() async {
        guard let settings else { return }
        guard settings.useCurrentLocation || !settings.locationName.isEmpty else {
            status = .needsCity
            current = nil
            return
        }
        if current == nil { status = .loading }

        do {
            let place: Place
            if settings.useCurrentLocation {
                place = try await locatePlace()
            } else {
                place = Place(name: settings.locationName, region: nil, country: nil,
                              latitude: settings.latitude, longitude: settings.longitude)
            }
            let unit = settings.temperatureUnit
            let forecast = try await Self.forecast(latitude: place.latitude, longitude: place.longitude, unit: unit)
            apply(forecast, place: place, unit: unit)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Current location and its name (cached while within 5 km).
    private func locatePlace() async throws -> Place {
        let location = try await locator.current()
        if let currentPlace,
           CLLocation(latitude: currentPlace.latitude, longitude: currentPlace.longitude).distance(from: location) < 5_000 {
            return currentPlace
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let place = Place(
            name: placemark?.locality ?? placemark?.administrativeArea ?? "Current Location",
            region: placemark?.administrativeArea, country: placemark?.country,
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        currentPlace = place
        return place
    }

    private func apply(_ f: ForecastResponse, place: Place, unit: TemperatureUnit) {
        let tz = TimeZone(secondsFromGMT: f.utcOffsetSeconds) ?? .current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = tz

        locationName = place.name
        timeZone = tz
        self.unit = unit
        current = Current(
            temperature: f.current.temperature,
            apparent: f.current.apparent,
            humidity: f.current.humidity,
            wind: f.current.wind,
            code: f.current.code,
            isDay: f.current.isDay == 1
        )

        // Hourly: start at the current hour.
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let currentHour = String(f.current.time.prefix(13)) + ":00"
        let start = f.hourly.time.firstIndex { $0 >= currentHour } ?? 0
        hours = f.hourly.time.indices.dropFirst(start).prefix(12).compactMap { i in
            guard let temp = f.hourly.temperature[i], let date = parser.date(from: f.hourly.time[i]) else { return nil }
            return Hour(id: f.hourly.time[i], date: date, temperature: temp,
                        code: f.hourly.code[i] ?? 0, isDay: (f.hourly.isDay[i] ?? 1) == 1)
        }

        sunrise = f.daily.sunrise.first.flatMap(parser.date(from:))
        sunset = f.daily.sunset.first.flatMap(parser.date(from:))

        parser.dateFormat = "yyyy-MM-dd"
        days = f.daily.time.indices.compactMap { i in
            guard let high = f.daily.high[i], let low = f.daily.low[i],
                  let date = parser.date(from: f.daily.time[i]) else { return nil }
            return Day(id: f.daily.time[i], date: date, code: f.daily.code[i] ?? 0, high: high, low: low,
                       precipitation: f.daily.precipitation[i].map { Int($0) })
        }
        updatedAt = Date()
    }

    // MARK: - Networking

    struct Place: Sendable, Identifiable, Hashable {
        let name: String
        let region: String?
        let country: String?
        let latitude: Double
        let longitude: Double

        var id: String { "\(latitude),\(longitude)" }
        var detail: String { [region, country].compactMap { $0 }.filter { !$0.isEmpty && $0 != name }.joined(separator: ", ") }
    }

    enum WeatherError: LocalizedError {
        case cityNotFound(String)
        var errorDescription: String? {
            switch self {
            case .cityNotFound(let city): "Couldn't find “\(city)”"
            }
        }
    }

    /// City search. "Paris, France" or "Portland, OR" narrows results by country or region.
    nonisolated static func search(_ query: String) async throws -> [Place] {
        let parts = query.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.first ?? query
        guard name.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let results = try JSONDecoder().decode(GeocodeResponse.self, from: data).results ?? []

        let qualifier = parts.dropFirst().joined(separator: " ").lowercased()
        let matching = results.filter { result in
            guard !qualifier.isEmpty else { return true }
            return [result.country, result.admin1, result.countryCode].compactMap { $0?.lowercased() }
                .contains { $0.contains(qualifier) || qualifier.contains($0) }
        }
        return (matching.isEmpty ? results : matching).map {
            Place(name: $0.name, region: $0.admin1, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    nonisolated static func geocode(_ query: String) async throws -> Place {
        guard let place = try await search(query).first else { throw WeatherError.cityNotFound(query) }
        return place
    }

    nonisolated static func forecast(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> ForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "temperature_unit", value: unit == .fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(ForecastResponse.self, from: data)
    }
}

// MARK: - API models

private struct GeocodeResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let countryCode: String?
        let admin1: String?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, country, admin1
            case countryCode = "country_code"
        }
    }
    let results: [Result]?
}

struct ForecastResponse: Decodable, Sendable {
    struct CurrentBlock: Decodable, Sendable {
        let time: String
        let temperature: Double
        let apparent: Double
        let humidity: Double
        let wind: Double
        let code: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparent = "apparent_temperature"
            case humidity = "relative_humidity_2m"
            case wind = "wind_speed_10m"
            case code = "weather_code"
            case isDay = "is_day"
        }
    }

    struct HourlyBlock: Decodable, Sendable {
        let time: [String]
        let temperature: [Double?]
        let code: [Int?]
        let isDay: [Int?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case code = "weather_code"
            case isDay = "is_day"
        }
    }

    struct DailyBlock: Decodable, Sendable {
        let time: [String]
        let code: [Int?]
        let high: [Double?]
        let low: [Double?]
        let precipitation: [Double?]
        let sunrise: [String]
        let sunset: [String]

        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case code = "weather_code"
            case high = "temperature_2m_max"
            case low = "temperature_2m_min"
            case precipitation = "precipitation_probability_max"
        }
    }

    let utcOffsetSeconds: Int
    let current: CurrentBlock
    let hourly: HourlyBlock
    let daily: DailyBlock

    enum CodingKeys: String, CodingKey {
        case current, hourly, daily
        case utcOffsetSeconds = "utc_offset_seconds"
    }
}

// MARK: - WMO weather codes

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing Drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy Rain"
        case 66, 67: "Freezing Rain"
        case 71, 73: "Snow"
        case 75: "Heavy Snow"
        case 77: "Snow Grains"
        case 80, 81: "Showers"
        case 82: "Heavy Showers"
        case 85, 86: "Snow Showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm & Hail"
        default: "—"
        }
    }
}
