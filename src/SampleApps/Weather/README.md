# Weather App Setup

This Weather app uses the OpenWeatherMap API to fetch real weather data.

## Getting an API Key

1. Go to [OpenWeatherMap](https://openweathermap.org/api)
2. Sign up for a free account
3. Navigate to API Keys section
4. Copy your API key

## Setting the API Key

1. Open `WeatherApp.swift`
2. Find the line: `private let apiKey = "YOUR_API_KEY_HERE"`
3. Replace `YOUR_API_KEY_HERE` with your actual API key
4. Example: `private let apiKey = "abc123def456ghi789"`

## Features

- Real-time weather data from OpenWeatherMap
- Location-based weather using CoreLocation
- City search functionality
- 5-day forecast
- Favorite cities
- Beautiful dynamic backgrounds based on weather conditions

## Permissions

The app requires location permissions to show weather for your current location. These are configured in `Info.plist`.

