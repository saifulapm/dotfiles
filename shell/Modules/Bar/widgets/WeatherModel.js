// Weather parsing/formatting layer — near-verbatim port of omarchy's
// plugins/panels/weather/Model.js (CREDITS.md). Their `parseWeatherStatus`
// (the status.sh bar-script bridge) is dropped: our widget reads the report
// directly. `parseLocationFile` takes the widget's inline settings entry
// instead of their weather.json, and `iconForCode` returns Material Design
// glyphs because the FontAwesome/weather ranges do not render under our
// Nerd Font fallback.

// Configured location from the widget's inline shell.json entry, with the
// legacy plain-text state file as a fallback so an existing
// ~/.local/state/qshell/weather-location keeps working. Missing, blank, or
// unparseable means the location is auto-detected from the IP address.
function parseLocationSettings(name, latitude, longitude, fallbackName) {
    const unset = {
        name: "",
        latitude: null,
        longitude: null
    };
    const trimmed = typeof name === "string" ? name.replace(/^\s+|\s+$/g, "") : "";
    if (trimmed === "") {
        const fallback = typeof fallbackName === "string" ? fallbackName.replace(/^\s+|\s+$/g, "") : "";
        if (fallback === "")
            return unset;
        return {
            name: fallback,
            latitude: null,
            longitude: null
        };
    }
    const lat = parseFloat(latitude);
    const lon = parseFloat(longitude);
    const hasCoordinates = !isNaN(lat) && !isNaN(lon);
    return {
        name: trimmed,
        latitude: hasCoordinates ? lat : null,
        longitude: hasCoordinates ? lon : null
    };
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback (a hand-edited
// location file only carries a name), empty for IP auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
    const lat = parseFloat(String(latitude));
    const lon = parseFloat(String(longitude));
    if (!isNaN(lat) && !isNaN(lon))
        return lat + "," + lon;

    const name = String(location || "").replace(/^\s+|\s+$/g, "");
    return name === "" ? "" : encodeURIComponent(name);
}

// Open-Meteo geocoding response → suggestion rows for the location picker.
function parseGeocodingResults(raw) {
    try {
        const data = JSON.parse(String(raw || "{}"));
        const results = data.results;
        if (!results || !results.length)
            return [];

        const out = [];
        for (let i = 0; i < results.length; i++) {
            const r = results[i];
            if (!r || !r.name || r.latitude === undefined || r.longitude === undefined)
                continue;
            const region = [r.admin1, r.country].filter(function (part) {
                return !!part;
            }).join(", ");
            out.push({
                name: String(r.name),
                description: region,
                latitude: r.latitude,
                longitude: r.longitude
            });
        }
        return out;
    } catch (e) {
        return [];
    }
}

function locationCommit(text, suggestions, selectedIndex) {
    const name = String(text || "").replace(/^\s+|\s+$/g, "");
    if (name === "")
        return {
            name: "",
            latitude: null,
            longitude: null
        };

    const choices = suggestions || [];
    const index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1));
    const suggestion = choices[index];
    if (suggestion)
        return suggestion;

    return {
        name: name,
        latitude: null,
        longitude: null
    };
}

function isFutureForecastDate(dateString, todayString) {
    if (!dateString)
        return false;
    return String(dateString).slice(0, 10) > String(todayString || "");
}

function roundedTemp(value) {
    if (value === undefined || value === null || value === "")
        return "";
    const n = parseFloat(String(value));
    return isNaN(n) ? "" : String(Math.round(n));
}

function celsiusToFahrenheit(value) {
    if (value === undefined || value === null || value === "")
        return "";
    const n = parseFloat(String(value));
    return isNaN(n) ? "" : (n * 9 / 5) + 32;
}

function formatTemp(value, useImperial) {
    if (value === undefined || value === null || value === "")
        return "";
    return value + "°" + (useImperial ? "F" : "C");
}

function normalizedUnit(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase();
}

function localeUsesImperial(localeName) {
    const name = String(localeName || "").replace(".", "_");
    return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name);
}

function countryUsesImperial(countryName) {
    const country = String(countryName || "").replace(/^\s+|\s+$/g, "").replace(/[._-]+/g, " ").toLowerCase();
    if (!country)
        return null;
    if (country === "us" || country === "usa" || country === "united states" || country === "united states of america")
        return true;
    if (country === "liberia" || country === "myanmar" || country === "burma")
        return true;
    return false;
}

function shouldUseImperial(unitOverride, localeName, countryName) {
    const unit = normalizedUnit(unitOverride);
    if (unit === "imperial")
        return true;
    if (unit === "metric")
        return false;

    const countryPreference = countryUsesImperial(countryName);
    if (countryPreference !== null)
        return countryPreference;

    return localeUsesImperial(localeName);
}

function dayName(dateString, formatter) {
    if (!dateString)
        return "";
    const d = new Date(dateString + "T12:00:00");
    if (isNaN(d.getTime()))
        return "";
    if (formatter)
        return formatter(d);
    return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()];
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
    const daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null;
    if (!daily || !daily.time)
        return [];

    const result = [];
    for (let i = 0; i < daily.time.length && result.length < 3; ++i) {
        const date = daily.time[i];
        if (!isFutureForecastDate(date, todayString))
            continue;

        const maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : "";
        const minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : "";
        result.push({
            date: date,
            maxtempC: roundedTemp(maxC),
            mintempC: roundedTemp(minC),
            maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
            mintempF: roundedTemp(celsiusToFahrenheit(minC)),
            openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
        });
    }
    return result;
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
function openMeteoCurrentCondition(dailyForecastReport) {
    const current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null;
    if (!current || current.temperature_2m === undefined || current.temperature_2m === null)
        return null;
    return {
        temp_C: roundedTemp(current.temperature_2m),
        temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
        FeelsLikeC: roundedTemp(current.apparent_temperature),
        FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
        windspeedKmph: roundedTemp(current.wind_speed_10m),
        windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
        humidity: roundedTemp(current.relative_humidity_2m),
        openMeteoWeatherCode: current.weather_code,
        isDay: current.is_day
    };
}

function currentDescription(current) {
    if (!current)
        return "";
    if (current.weatherDesc && current.weatherDesc[0] && current.weatherDesc[0].value)
        return String(current.weatherDesc[0].value);
    if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
        return openMeteoDescription(current.openMeteoWeatherCode);
    return "";
}

// Open-Meteo answers with WMO codes and no text; wttr.in ships the wording.
// These are the WMO descriptions for the codes iconForOpenMeteoCode groups.
function openMeteoDescription(code) {
    const c = parseInt(String(code || "0"), 10);
    if (c === 0)
        return "Clear";
    if (c === 1)
        return "Mainly clear";
    if (c === 2)
        return "Partly cloudy";
    if (c === 3)
        return "Overcast";
    if (c === 45 || c === 48)
        return "Fog";
    if (c === 51 || c === 53 || c === 55)
        return "Drizzle";
    if (c === 56 || c === 57)
        return "Freezing drizzle";
    if (c === 61 || c === 63 || c === 65)
        return "Rain";
    if (c === 66 || c === 67)
        return "Freezing rain";
    if (c === 71 || c === 73 || c === 75)
        return "Snow";
    if (c === 77)
        return "Snow grains";
    if (c === 80 || c === 81 || c === 82)
        return "Rain showers";
    if (c === 85 || c === 86)
        return "Snow showers";
    if (c === 95)
        return "Thunderstorm";
    if (c === 96 || c === 99)
        return "Thunderstorm with hail";
    return "";
}

function currentIcon(current, fallback) {
    if (!current)
        return fallback || "";
    if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
        return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0);
    if (current.weatherCode !== undefined && current.weatherCode !== null)
        return iconForCode(current.weatherCode, false);
    return fallback || "";
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
    return resolvedIcon || currentIcon(current, "");
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
    return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr";
}

function wttrNextForecastDays(report, todayString) {
    const days = report && report.weather ? report.weather : [];
    const result = [];
    for (let i = 0; i < days.length && result.length < 3; ++i) {
        if (isFutureForecastDate(days[i].date, todayString))
            result.push(days[i]);
    }
    return result;
}

function buildForecastDays(report, dailyForecastReport, todayString) {
    const days = openMeteoForecastDays(dailyForecastReport, todayString);
    return days.length > 0 ? days : wttrNextForecastDays(report, todayString);
}

function bareTempForDay(day, kind, useImperial) {
    if (!day)
        return "";
    const v = useImperial ? (kind === "max" ? day.maxtempF : day.mintempF) : (kind === "max" ? day.maxtempC : day.mintempC);
    if (v === undefined || v === null || v === "")
        return "";
    return v + "°";
}

// Representative icon for a forecast day: the hourly entry nearest noon.
function dayIcon(day) {
    if (!day)
        return "";
    if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
        return iconForOpenMeteoCode(day.openMeteoWeatherCode);
    if (!day.hourly || day.hourly.length === 0)
        return "";

    let best = day.hourly[0];
    let bestDist = 9999;
    for (let i = 0; i < day.hourly.length; ++i) {
        const t = parseInt(String(day.hourly[i].time || "0"), 10);
        const dist = Math.abs(t - 1200);
        if (dist < bestDist) {
            bestDist = dist;
            best = day.hourly[i];
        }
    }
    return iconForCode(best.weatherCode, false);
}

function iconForOpenMeteoCode(code, night) {
    const c = parseInt(String(code || "0"), 10);
    if (c === 0)
        return iconForCode(113, night);
    if (c === 1 || c === 2)
        return iconForCode(116, night);
    if (c === 3)
        return iconForCode(119, night);
    if (c === 45 || c === 48)
        return iconForCode(143, night);
    if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61)
        return iconForCode(266, night);
    if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82)
        return iconForCode(308, night);
    if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86)
        return iconForCode(338, night);
    if (c === 95 || c === 96 || c === 99)
        return iconForCode(389, night);
    return iconForCode(119, night);
}

// omarchy's wttr.in code groups (from omarchy-weather-icon), with their
// day/night split. Their glyphs are FontAwesome/weather-range; these are the
// Material Design equivalents, which are what renders here. The one addition
// is splitting their single rain group into drizzle/light rain (rainy) and
// moderate/heavy rain (pouring) — both glyphs exist in the MD set.
function iconForCode(code, night) {
    const c = parseInt(String(code || "0"), 10);
    switch (c) {
    case 113:
        return night ? "󰖔" : "󰖙";           // clear
    case 116:
        return night ? "󰼱" : "󰖕";           // partly cloudy
    case 119:
    case 122:
        return "󰖐";                          // cloudy / overcast
    case 143:
    case 248:
    case 260:
        return "󰖑";                          // mist / fog / freezing fog
    case 176:
    case 263:
    case 353:
        return "󰼳";                          // patchy / light rain shower
    case 179:
    case 227:
    case 230:
    case 323:
    case 326:
    case 368:
        return "󰼴";                          // patchy / blowing snow, blizzard
    case 182:
    case 185:
    case 281:
    case 284:
    case 311:
    case 314:
    case 317:
    case 320:
    case 350:
    case 362:
    case 365:
    case 374:
    case 377:
        return "󰙿";                          // sleet, freezing drizzle, ice pellets
    case 200:
    case 386:
    case 389:
    case 392:
    case 395:
        return "󰖓";                          // thundery outbreaks
    case 266:
    case 293:
    case 296:
        return "󰖗";                          // drizzle / light rain
    case 299:
    case 302:
    case 305:
    case 308:
    case 356:
    case 359:
        return "󰖖";                          // moderate to torrential rain
    case 329:
    case 332:
    case 335:
    case 338:
    case 371:
        return "󰖘";                          // snow
    default:
        return "󰖐";
    }
}
