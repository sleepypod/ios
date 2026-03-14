import React, { useState } from 'react'
import { Wifi, RefreshCw, ChevronDown, ChevronRight, Download, CheckCircle, Clock, Tag, Settings, Zap } from 'lucide-react'

function SettingsScreen() {
  const [tempUnit, setTempUnit] = useState<'celsius' | 'fahrenheit'>('fahrenheit')
  const [autoReboot, setAutoReboot] = useState(true)
  const [ledBrightness, setLedBrightness] = useState(75)
  const [hasUpdate, setHasUpdate] = useState(true)

  const currentVersion = 'v1.0.0'
  const newVersion = 'v2.1.3'

  const updateChangelog = [
    'Improved temperature control accuracy',
    'Fixed scheduling bug for recurring alarms',
    'Added new biometrics dashboard',
  ]

  return (
    <div className="screen-content settings-screen">
      {/* Device Settings Card */}
      <div className="settings-card device-settings-card">
        <h3 className="device-settings-title">Device settings</h3>

        {/* Timezone */}
        <div className="setting-item">
          <span className="setting-label-text">Time Zone</span>
          <button className="timezone-select">
            <span>America/Los_Angeles</span>
            <ChevronDown size={18} />
          </button>
        </div>

        {/* Temperature Unit Toggle */}
        <div className="temp-unit-toggle">
          <button
            className={`unit-btn ${tempUnit === 'celsius' ? '' : 'inactive'}`}
            onClick={() => setTempUnit('celsius')}
          >
            CELSIUS
          </button>
          <button
            className={`unit-btn ${tempUnit === 'fahrenheit' ? 'active' : 'inactive'}`}
            onClick={() => setTempUnit('fahrenheit')}
          >
            FAHRENHEIT
          </button>
        </div>

        {/* Auto Reboot */}
        <div className="setting-item reboot-setting">
          <div className="setting-text">
            <span className="setting-label-text">Reboot once a day</span>
            <span className="setting-description">
              Automatically reboot the Pod once per day to keep it running smoothly. Reboot time is scheduled 1 hour before the daily prime time.
            </span>
          </div>
          <button
            className={`toggle-switch ${autoReboot ? 'active' : ''}`}
            onClick={() => setAutoReboot(!autoReboot)}
          >
            <span className="toggle-knob" />
          </button>
        </div>

        {/* LED Brightness */}
        <div className="setting-item brightness-setting">
          <span className="setting-label-text">LED Brightness</span>
          <div className="brightness-slider">
            <input
              type="range"
              min="0"
              max="100"
              value={ledBrightness}
              onChange={(e) => setLedBrightness(Number(e.target.value))}
              className="slider"
            />
            <div className="slider-labels">
              <span>Off</span>
              <span>100%</span>
            </div>
          </div>
        </div>

        {/* Device Info Tags */}
        <div className="device-tags">
          <span className="device-tag">Device: Pod 3 Cover</span>
          <span className="device-tag">Pod 3 Hub</span>
        </div>
        <div className="device-tags">
          <span className="device-tag">Free Sleep Build: v1.2.0</span>
          <span className="device-tag">main</span>
        </div>

        {/* Action Buttons */}
        <div className="action-buttons">
          <button className="action-btn reboot-btn">
            <RefreshCw size={18} />
            <span>REBOOT POD NOW</span>
          </button>
          <button className="action-btn wifi-btn">
            <Wifi size={18} />
            <span>WiFi Strength 82%</span>
          </button>
        </div>
      </div>

      {/* Update Card */}
      {hasUpdate ? (
        <div className="settings-card update-card has-update">
          <div className="update-header">
            <Zap size={20} className="update-icon" />
            <span className="update-title">Update Available</span>
            <span className="update-badge">NEW</span>
          </div>

          <div className="version-transition">
            <span className="version-tag old">{currentVersion}</span>
            <span className="version-arrow">→</span>
            <span className="version-tag new">{newVersion}</span>
          </div>

          <div className="changelog">
            <div className="changelog-header">
              <Tag size={14} />
              <span>WHAT'S NEW</span>
            </div>
            <ul className="changelog-list">
              {updateChangelog.map((item, idx) => (
                <li key={idx}>{item}</li>
              ))}
            </ul>
          </div>

          <button className="update-btn" onClick={() => setHasUpdate(false)}>
            <Download size={18} />
            <span>Update to {newVersion}</span>
          </button>

          <button className="advanced-link">
            <Settings size={16} />
            <span>Advanced Options</span>
            <ChevronRight size={16} />
          </button>
        </div>
      ) : (
        <div className="settings-card update-card up-to-date">
          <div className="uptodate-header">
            <CheckCircle size={24} className="check-icon" />
            <span className="uptodate-title">Software Up to Date</span>
          </div>

          <span className="version-tag current">
            <Tag size={14} />
            {newVersion}
          </span>

          <div className="last-check">
            <Clock size={14} />
            <span>Last checked: 2 hours ago</span>
          </div>

          <button className="check-btn">
            <RefreshCw size={16} />
            <span>Check for Updates</span>
          </button>

          <button className="advanced-link">
            <Settings size={16} />
            <span>Advanced Options</span>
            <ChevronRight size={16} />
          </button>
        </div>
      )}
    </div>
  )
}

export default SettingsScreen
