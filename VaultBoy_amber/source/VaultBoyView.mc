import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.Timer;

class VaultBoyView extends WatchUi.WatchFace {
    private var _currentFrame = 0;
    private var _animationTimer as Timer.Timer?;
    private var _ready = false;
    private var _timerRunning = false;
    private var _isHighPower = false;

    private const THEME_COLOR = 0xFFBF00;

    private var _assetText as WatchUi.BitmapResource?;
    private var _assetBat  as WatchUi.BitmapResource?;
    private var _assetBeat as WatchUi.BitmapResource?;
    private var _frames as Array<WatchUi.BitmapResource?> = [null, null, null, null, null, null, null, null, null] as Array<WatchUi.BitmapResource?>;

    private var _cachedSteps = -1, _cachedCalories = -1, _cachedFloors = -1;
    private var _cachedBatt = -1, _cachedBodyBatt = -1, _cachedSolar = -1;
    private var _solarSamples as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    private var _solarSampleIdx = 0;
    private var _solarSampleCount = 0;
    private var _cachedHR = "--", _cachedTemp = "--", _cachedCond = "NONE";

    private var _strTime = "", _strDate = "", _strBatt = "";
    private var _strSteps = "0", _strCalories = "0", _strFloors = "0";
    private var _strBodyBatt = "0", _strSolar = "0", _strHR = "--";

    private var _frameCounter = 0;
    private var _lastMinute = -1;
    private var _weatherCounter = 0;
    private var _bodyBattCounter = 0;

    private const ACTIVITY_EVERY     = 30;
    private const HR_EVERY           = 10;
    private const CALORIES_EVERY     = 1500;
    private const BATTERY_EVERY      = 1500;
    private const SOLAR_SAMPLE_EVERY = 150;
    private const SOLAR_SAMPLES      = 10;
    private const BODYBATT_EVERY     = 1500;
    private const WEATHER_EVERY      = 1500;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _ready = false;
        _assetText = WatchUi.loadResource(Rez.Drawables.Text)   as WatchUi.BitmapResource;
        _assetBat  = WatchUi.loadResource(Rez.Drawables.Bat)    as WatchUi.BitmapResource;
        _assetBeat = WatchUi.loadResource(Rez.Drawables.Beat)   as WatchUi.BitmapResource;
        var resIds = [
            Rez.Drawables.Vault_0, Rez.Drawables.Vault_1, Rez.Drawables.Vault_2,
            Rez.Drawables.Vault_3, Rez.Drawables.Vault_4, Rez.Drawables.Vault_5,
            Rez.Drawables.Vault_6, Rez.Drawables.Vault_7, Rez.Drawables.Vault_8
        ];
        for (var i = 0; i < 9; i++) {
            _frames[i] = WatchUi.loadResource(resIds[i]) as WatchUi.BitmapResource;
        }
        _ready = true;
    }

    function onExitSleep() as Void {
        _isHighPower = false;
        _bodyBattCounter = BODYBATT_EVERY;
        _weatherCounter  = WEATHER_EVERY;
        startTimer(140);
    }

    function onEnterSleep() as Void {
        _isHighPower = false;
        stopTimer();
    }

    function onShow() as Void {
        _isHighPower = true;
        _currentFrame = 0;
        _weatherCounter  = WEATHER_EVERY;
        _bodyBattCounter = BODYBATT_EVERY;
        _lastMinute = -1;
        startTimer(140);
    }

    function onHide() as Void { stopTimer(); }

    function startTimer(intervalMs as Lang.Number) as Void {
        stopTimer();
        _animationTimer = new Timer.Timer();
        _animationTimer.start(method(:triggerRefresh), intervalMs, true);
        _timerRunning = true;
    }

    function stopTimer() as Void {
        if (_animationTimer != null) {
            _animationTimer.stop();
            _animationTimer = null;
        }
        _timerRunning = false;
    }

    function triggerRefresh() as Void { WatchUi.requestUpdate(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (!_ready) { return; }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        updateData();

        if (_assetText != null) { dc.drawBitmap(17, 95, _assetText); }
        if (_assetBeat != null) { dc.drawBitmap(227, 109, _assetBeat); }
        if (_assetBat  != null) { dc.drawBitmap(47, 197, _assetBat); }

        drawStaticUI(dc);

        var frame = _frames[_currentFrame];
        if (frame != null) { dc.drawBitmap(175, 85, frame as WatchUi.BitmapResource); }

        dc.setPenWidth(1);
        dc.setColor(THEME_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(215, 76, 238, 76);   dc.drawLine(238, 76, 238, 104);
        dc.drawLine(238, 150, 238, 180); dc.drawLine(238, 180, 215, 180);

        _currentFrame = (_currentFrame + 1) % 9;
        _frameCounter++;
    }

    function updateData() as Void {
        var clockTime = System.getClockTime();
        if (clockTime.min != _lastMinute) {
            _lastMinute = clockTime.min;
            _strTime = clockTime.hour.format("%02d") + ":" + clockTime.min.format("%02d");
            var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            _strDate = info.day_of_week.toUpper() + " " + info.month.toUpper() + " " + info.day;
        }

        if (_frameCounter % ACTIVITY_EVERY == 0 || _frameCounter % CALORIES_EVERY == 0) {
            var ai = ActivityMonitor.getInfo();
            if (ai != null) {
                if (_frameCounter % ACTIVITY_EVERY == 0) {
                    var s = (ai.steps         != null) ? ai.steps         : 0;
                    var f = (ai.floorsClimbed != null) ? ai.floorsClimbed : 0;
                    if (s != _cachedSteps)  { _cachedSteps  = s; _strSteps  = s.toString(); }
                    if (f != _cachedFloors) { _cachedFloors = f; _strFloors = f.toString(); }
                }
                if (_frameCounter % CALORIES_EVERY == 0) {
                    var c = (ai.calories != null) ? ai.calories : 0;
                    if (c != _cachedCalories) { _cachedCalories = c; _strCalories = c.toString(); }
                }
            }
        }

        if (_frameCounter % HR_EVERY == 0) {
            var act = Activity.getActivityInfo();
            var hr = (act != null && act.currentHeartRate != null) ? act.currentHeartRate.toString() : "--";
            if (!hr.equals(_cachedHR)) { _cachedHR = hr; _strHR = hr; }
        }

        if (_frameCounter % BATTERY_EVERY == 0 || _frameCounter % SOLAR_SAMPLE_EVERY == 0) {
            var stats = System.getSystemStats();
            if (stats != null) {
                if (_frameCounter % BATTERY_EVERY == 0) {
                    var b = stats.battery.toNumber();
                    if (b != _cachedBatt) { _cachedBatt = b; _strBatt = b.toString() + "%"; }
                }
                if (_frameCounter % SOLAR_SAMPLE_EVERY == 0) {
                    var sol = (stats has :solarIntensity) ? stats.solarIntensity as Number : 0;
                    _solarSamples[_solarSampleIdx] = sol;
                    _solarSampleIdx = (_solarSampleIdx + 1) % SOLAR_SAMPLES;
                    if (_solarSampleCount < SOLAR_SAMPLES) { _solarSampleCount++; }
                    var sum = 0;
                    var n = _solarSampleCount > 0 ? _solarSampleCount : 1;
                    for (var i = 0; i < n; i++) { sum += _solarSamples[i]; }
                    var avg = (sum / n).toNumber();
                    if (avg != _cachedSolar) { _cachedSolar = avg; _strSolar = avg.toString(); }
                }
            }
        }

        _bodyBattCounter++;
        if (_bodyBattCounter >= BODYBATT_EVERY) {
            _bodyBattCounter = 0;
            if (Toybox has :SensorHistory && SensorHistory has :getBodyBatteryHistory) {
                var iter = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    var bb = sample.data.toNumber();
                    if (bb != _cachedBodyBatt) { _cachedBodyBatt = bb; _strBodyBatt = bb.toString(); }
                }
            }
        }

        _weatherCounter++;
        if (_weatherCounter >= WEATHER_EVERY) {
            _weatherCounter = 0;
            var weather = Weather.getCurrentConditions();
            if (weather != null) {
                _cachedTemp = (weather.temperature != null) ? weather.temperature.toNumber().toString() + "°C" : "--";
                var c = weather.condition;
                _cachedCond = (c == Weather.CONDITION_CLEAR) ? "CLEAR" : "FAIR";
            }
        }
    }

    function drawStaticUI(dc as Graphics.Dc) as Void {
        dc.setColor(THEME_COLOR, Graphics.COLOR_TRANSPARENT);

        dc.drawText(101, 29,  Graphics.FONT_NUMBER_MEDIUM, _strTime,    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(130, 12,  Graphics.FONT_SYSTEM_XTINY,  _strDate,    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(161, 42,  Graphics.FONT_SYSTEM_XTINY,  _cachedCond, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(161, 59,  Graphics.FONT_SYSTEM_XTINY,  _cachedTemp, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(238, 128, Graphics.FONT_SYSTEM_XTINY,  _strHR,      Graphics.TEXT_JUSTIFY_CENTER);

        drawVaultBar(dc, 53, 109, 102, 10, 1, THEME_COLOR, _cachedSteps.toFloat()    / 10000.0);
        dc.drawText(155, 92,  Graphics.FONT_SYSTEM_XTINY, _strSteps,    Graphics.TEXT_JUSTIFY_RIGHT);

        drawVaultBar(dc, 53, 138, 102, 10, 1, THEME_COLOR, _cachedFloors.toFloat()   / 10.0);
        dc.drawText(155, 121, Graphics.FONT_SYSTEM_XTINY, _strFloors,   Graphics.TEXT_JUSTIFY_RIGHT);

        drawVaultBar(dc, 53, 168, 102, 10, 1, THEME_COLOR, _cachedSolar.toFloat()    / 100.0);
        dc.drawText(155, 151, Graphics.FONT_SYSTEM_XTINY, _strSolar,    Graphics.TEXT_JUSTIFY_RIGHT);

        drawVaultBar(dc, 125, 216, 85, 12, 2, 0x555555,    _cachedBodyBatt.toFloat() / 100.0);
        dc.drawText(168, 196, Graphics.FONT_SYSTEM_XTINY, _strBodyBatt, Graphics.TEXT_JUSTIFY_RIGHT);

        drawVaultBar(dc, 51, 217, 18, 12, 0, THEME_COLOR,  _cachedBatt.toFloat()     / 100.0);
        dc.drawText(116, 213, Graphics.FONT_SYSTEM_XTINY, _strBatt,     Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(116, 196, Graphics.FONT_SYSTEM_XTINY, _strCalories, Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(THEME_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(80, 15, 80, 32);     dc.drawLine(80, 32, 50, 32);
        dc.drawLine(180, 15, 180, 32);   dc.drawLine(180, 32, 210, 32);
        dc.drawLine(123, 200, 123, 230); dc.drawLine(123, 230, 223, 230);
    }

    function drawVaultBar(dc, x, y, width, height, trackStyle, trackColor, fillRatio) as Void {
        if (fillRatio > 1.0) { fillRatio = 1.0; }
        if (fillRatio < 0.0) { fillRatio = 0.0; }
        dc.setColor(trackColor, Graphics.COLOR_TRANSPARENT);
        if (trackStyle == 1) {
            var centerY = y + (height / 2);
            dc.drawLine(x, centerY, x + width, centerY);
            if (fillRatio > 0) {
                dc.setColor(THEME_COLOR, Graphics.COLOR_TRANSPARENT);
                var fillHeight = 6;
                var fillY = centerY - (fillHeight / 2);
                dc.fillRectangle(x, fillY, (width * fillRatio).toNumber(), fillHeight);
            }
        } else {
            if (fillRatio > 0) {
                dc.setColor(THEME_COLOR, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, y, (width * fillRatio).toNumber(), height);
            }
        }
    }
}
