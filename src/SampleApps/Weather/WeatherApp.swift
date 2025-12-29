/**
 * Weather - Fully Functional iOS Weather App
 * Uses OpenWeatherMap API for real weather data
 * Supports location-based weather and city search
 */

import SwiftUI
import CoreLocation

// @main - Removed
struct WeatherApp: App {
    var body: some Scene {
        WindowGroup {
            WeatherView()
        }
    }
}

// MARK: - Weather Models

struct WeatherResponse: Codable {
    let name: String
    let main: MainWeather
    let weather: [WeatherCondition]
    let wind: Wind
    let sys: System
    let coord: Coordinates
    
    struct MainWeather: Codable {
        let temp: Double
        let feelsLike: Double
        let tempMin: Double
        let tempMax: Double
        let humidity: Int
        let pressure: Int
    }
    
    struct WeatherCondition: Codable {
        let main: String
        let description: String
        let icon: String
    }
    
    struct Wind: Codable {
        let speed: Double
        let deg: Int?
    }
    
    struct System: Codable {
        let country: String
        let sunrise: TimeInterval?
        let sunset: TimeInterval?
    }
    
    struct Coordinates: Codable {
        let lat: Double
        let lon: Double
    }
}

struct ForecastResponse: Codable {
    let list: [ForecastItem]
    
    struct ForecastItem: Codable {
        let dt: TimeInterval
        let main: MainWeather
        let weather: [WeatherCondition]
        let wind: Wind
        
        struct MainWeather: Codable {
            let temp: Double
            let tempMin: Double
            let tempMax: Double
            let humidity: Int
        }
        
        struct WeatherCondition: Codable {
            let main: String
            let description: String
            let icon: String
        }
        
        struct Wind: Codable {
            let speed: Double
        }
    }
}

// MARK: - Weather Service

class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentWeather: WeatherResponse?
    @Published var forecast: ForecastResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var locationName: String = "Loading..."
    
    private let apiKey = "YOUR_API_KEY_HERE" // Replace with your OpenWeatherMap API key
    private let baseURL = "https://api.openweathermap.org/data/2.5"
    let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        currentLocation = location
        fetchWeatherForLocation(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
        // Fallback to default city
        fetchWeatherForCity("San Francisco")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied. Using default city."
            fetchWeatherForCity("San Francisco")
        default:
            break
        }
    }
    
    func fetchWeatherForCity(_ city: String) {
        isLoading = true
        errorMessage = nil
        
        let urlString = "\(baseURL)/weather?q=\(city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city)&appid=\(apiKey)&units=metric"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self?.currentWeather = weather
                    self?.locationName = "\(weather.name), \(weather.sys.country)"
                    self?.fetchForecast(lat: weather.coord.lat, lon: weather.coord.lon)
                } catch {
                    self?.errorMessage = "Failed to parse weather data: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func fetchWeatherForLocation(lat: Double, lon: Double) {
        isLoading = true
        errorMessage = nil
        
        let urlString = "\(baseURL)/weather?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=metric"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self?.currentWeather = weather
                    self?.locationName = "\(weather.name), \(weather.sys.country)"
                    self?.fetchForecast(lat: lat, lon: lon)
                } catch {
                    self?.errorMessage = "Failed to parse weather data: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func fetchForecast(lat: Double, lon: Double) {
        let urlString = "\(baseURL)/forecast?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=metric"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else { return }
                
                do {
                    let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data)
                    self?.forecast = forecast
                } catch {
                    print("Forecast error: \(error)")
                }
            }
        }.resume()
    }
    
    func refresh() {
        if let location = currentLocation {
            fetchWeatherForLocation(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        } else if let weather = currentWeather {
            fetchWeatherForCity(weather.name)
        } else {
            locationManager.requestLocation()
        }
    }
}

// MARK: - Weather View

struct WeatherView: View {
    @StateObject private var weatherService = WeatherService()
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var favoriteCities: [String] = UserDefaults.standard.stringArray(forKey: "FavoriteCities") ?? ["San Francisco", "New York", "Tokyo", "London"]
    @State private var selectedCity: String?
    
    var body: some View {
        ZStack {
            // Dynamic background
            backgroundGradient
                .ignoresSafeArea()
            
            if weatherService.isLoading && weatherService.currentWeather == nil {
                ProgressView()
                    .tint(.white)
            } else if let error = weatherService.errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
                        weatherService.refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let weather = weatherService.currentWeather {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header with location and search
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weatherService.locationName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Updated \(formatTime(Date()))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Button(action: { showSearch.toggle() }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            
                            Button(action: { weatherService.refresh() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)
                        
                        // Current weather
                        VStack(spacing: 10) {
                            Image(systemName: weatherIcon(for: weather.weather.first?.icon ?? ""))
                                .font(.system(size: 120))
                                .foregroundColor(.white)
                                .shadow(radius: 10)
                            
                            Text("\(Int(weather.main.temp))°")
                                .font(.system(size: 90, weight: .thin))
                                .foregroundColor(.white)
                            
                            Text(weather.weather.first?.description.capitalized ?? "")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.9))
                            
                            Text("Feels like \(Int(weather.main.feelsLike))°")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.vertical, 30)
                        
                        // High/Low
                        HStack(spacing: 30) {
                            Label("H: \(Int(weather.main.tempMax))°", systemImage: "arrow.up")
                            Label("L: \(Int(weather.main.tempMin))°", systemImage: "arrow.down")
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .font(.headline)
                        
                        // Details card
                        VStack(spacing: 20) {
                            HStack(spacing: 40) {
                                DetailItem(icon: "humidity.fill", value: "\(weather.main.humidity)%", label: "Humidity")
                                DetailItem(icon: "wind", value: "\(Int(weather.wind.speed)) m/s", label: "Wind")
                            }
                            
                            HStack(spacing: 40) {
                                DetailItem(icon: "gauge", value: "\(weather.main.pressure) hPa", label: "Pressure")
                                if let sunrise = weather.sys.sunrise {
                                    DetailItem(icon: "sunrise.fill", value: formatTime(Date(timeIntervalSince1970: sunrise)), label: "Sunrise")
                                }
                            }
                            
                            if let sunset = weather.sys.sunset {
                                DetailItem(icon: "sunset.fill", value: formatTime(Date(timeIntervalSince1970: sunset)), label: "Sunset")
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.horizontal)
                        
                        // Forecast
                        if let forecast = weatherService.forecast {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("5-Day Forecast")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                ForEach(Array(forecast.list.prefix(5).enumerated()), id: \.offset) { index, item in
                                    ForecastRow(item: item)
                                }
                            }
                            .padding(.vertical)
                        }
                        
                        // Favorite cities
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Favorite Cities")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(favoriteCities, id: \.self) { city in
                                        Button(action: {
                                            selectedCity = city
                                            weatherService.fetchWeatherForCity(city)
                                        }) {
                                            Text(city)
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(selectedCity == city ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .padding(.vertical)
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(weatherService: weatherService, favoriteCities: $favoriteCities)
        }
        .onAppear {
            if weatherService.currentWeather == nil {
                weatherService.locationManager.requestLocation()
            }
        }
    }
    
    var backgroundGradient: LinearGradient {
        guard let weather = weatherService.currentWeather,
              let icon = weather.weather.first?.icon else {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
        }
        
        switch icon {
        case "01d", "01n": // Clear
            return LinearGradient(colors: [.orange, .yellow, .orange.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case "02d", "02n", "03d", "03n", "04d", "04n": // Clouds
            return LinearGradient(colors: [.gray.opacity(0.8), .blue.opacity(0.5), .gray.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case "09d", "09n", "10d", "10n": // Rain
            return LinearGradient(colors: [.gray, .blue.opacity(0.6), .gray.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case "11d", "11n": // Thunderstorm
            return LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6), .gray], startPoint: .top, endPoint: .bottom)
        case "13d", "13n": // Snow
            return LinearGradient(colors: [.white.opacity(0.9), .blue.opacity(0.3), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case "50d", "50n": // Mist/Fog
            return LinearGradient(colors: [.gray.opacity(0.7), .white.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.blue, .cyan, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        }
    }
    
    func weatherIcon(for iconCode: String) -> String {
        switch iconCode {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d", "03d", "04d": return "cloud.sun.fill"
        case "02n", "03n", "04n": return "cloud.moon.fill"
        case "09d", "09n": return "cloud.rain.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "cloud.snow.fill"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DetailItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .foregroundColor(.white)
    }
}

struct ForecastRow: View {
    let item: ForecastResponse.ForecastItem
    
    var body: some View {
        HStack {
            Text(formatDate(item.dt))
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.white)
            
            Image(systemName: weatherIcon(for: item.weather.first?.icon ?? ""))
                .foregroundColor(.white)
                .frame(width: 40)
            
            Text(item.weather.first?.description.capitalized ?? "")
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("\(Int(item.main.tempMax))°/\(Int(item.main.tempMin))°")
                .foregroundColor(.white)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    func formatDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
    
    func weatherIcon(for iconCode: String) -> String {
        switch iconCode {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d", "03d", "04d": return "cloud.sun.fill"
        case "02n", "03n", "04n": return "cloud.moon.fill"
        case "09d", "09n": return "cloud.rain.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "cloud.snow.fill"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
}

struct SearchView: View {
    @ObservedObject var weatherService: WeatherService
    @Binding var favoriteCities: [String]
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Search city...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onSubmit {
                        if !searchText.isEmpty {
                            weatherService.fetchWeatherForCity(searchText)
                            dismiss()
                        }
                    }
                
                List {
                    ForEach(favoriteCities, id: \.self) { city in
                        Button(action: {
                            weatherService.fetchWeatherForCity(city)
                            dismiss()
                        }) {
                            Text(city)
                        }
                    }
                    .onDelete { indexSet in
                        favoriteCities.remove(atOffsets: indexSet)
                        UserDefaults.standard.set(favoriteCities, forKey: "FavoriteCities")
                    }
                }
            }
            .navigationTitle("Search City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
