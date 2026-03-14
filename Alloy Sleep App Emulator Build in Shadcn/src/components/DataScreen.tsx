import React, { useState } from 'react'
import { ChevronLeft, ChevronRight, Moon, Sun, Clock, BedDouble, Heart, Activity, Wind, Droplets, Move } from 'lucide-react'

function DataScreen() {
  const [selectedWeek, setSelectedWeek] = useState({ start: 'Dec 9', end: 'Dec 15, 2024' })
  const [selectedDay, setSelectedDay] = useState(6) // Sunday

  const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

  // Weekly sleep timeline data (hours shown as bar heights)
  const weeklyData = [
    { day: 'Mon', sleepHours: 7.5, bedtime: '11:00 PM', wakeTime: '6:30 AM' },
    { day: 'Tue', sleepHours: 6.8, bedtime: '11:30 PM', wakeTime: '6:20 AM' },
    { day: 'Wed', sleepHours: 7.2, bedtime: '10:45 PM', wakeTime: '6:00 AM' },
    { day: 'Thu', sleepHours: 7.0, bedtime: '11:00 PM', wakeTime: '6:00 AM' },
    { day: 'Fri', sleepHours: 6.5, bedtime: '12:00 AM', wakeTime: '6:30 AM' },
    { day: 'Sat', sleepHours: 8.2, bedtime: '11:00 PM', wakeTime: '7:15 AM' },
    { day: 'Sun', sleepHours: 8.5, bedtime: '10:30 PM', wakeTime: '7:00 AM' },
  ]

  const selectedDayData = weeklyData[selectedDay]

  // Health metrics
  const healthMetrics = {
    avgHR: 55,
    hrv: 63,
    breath: 12,
    minHR: 45,
    maxHR: 68,
    spo2: 96,
  }

  // Sleep stages timeline data
  const sleepStages = [
    { time: '11:00', stage: 'light' },
    { time: '11:30', stage: 'deep' },
    { time: '12:00', stage: 'deep' },
    { time: '12:30', stage: 'light' },
    { time: '1:00', stage: 'rem' },
    { time: '1:30', stage: 'light' },
    { time: '2:00', stage: 'deep' },
    { time: '2:30', stage: 'light' },
    { time: '3:00', stage: 'light' },
    { time: '3:30', stage: 'deep' },
    { time: '4:00', stage: 'rem' },
    { time: '4:30', stage: 'light' },
    { time: '5:00', stage: 'rem' },
    { time: '5:30', stage: 'light' },
    { time: '6:00', stage: 'rem' },
    { time: '6:30', stage: 'awake' },
  ]

  // Movement data
  const movementData = {
    positionChanges: 23,
    timeStill: 92,
    restlessness: 'Low',
    restlessMin: 12,
  }

  const changeWeek = (delta: number) => {
    // Simplified week change
    if (delta > 0) {
      setSelectedWeek({ start: 'Dec 16', end: 'Dec 22, 2024' })
    } else {
      setSelectedWeek({ start: 'Dec 2', end: 'Dec 8, 2024' })
    }
  }

  return (
    <div className="screen-content data-screen">
      {/* Week Navigator */}
      <div className="date-navigator">
        <button className="date-nav-btn" onClick={() => changeWeek(-1)}>
          <ChevronLeft size={20} />
        </button>
        <span className="current-date">{selectedWeek.start} - {selectedWeek.end}</span>
        <button className="date-nav-btn" onClick={() => changeWeek(1)}>
          <ChevronRight size={20} />
        </button>
      </div>

      {/* Sleep Timeline (Weekly View) */}
      <div className="data-card timeline-card">
        <h3 className="card-title">SLEEP TIMELINE</h3>
        <div className="timeline-chart">
          <div className="timeline-labels">
            <span>4am</span>
            <span>12am</span>
            <span>8pm</span>
          </div>
          <div className="timeline-bars">
            {weeklyData.map((day, idx) => (
              <button
                key={idx}
                className={`timeline-bar-wrapper ${selectedDay === idx ? 'selected' : ''}`}
                onClick={() => setSelectedDay(idx)}
              >
                <div
                  className="timeline-bar"
                  style={{ height: `${(day.sleepHours / 10) * 100}%` }}
                />
                <span className="timeline-day">{day.day}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Sleep Summary */}
      <div className="data-card summary-card">
        <div className="summary-header">
          <h3 className="summary-title">Sleep Summary</h3>
          <span className="summary-date">Sunday, Dec 15</span>
          <span className="summary-trend positive">↗ 5%</span>
        </div>
        <div className="summary-grid">
          <div className="summary-item">
            <Moon size={18} className="summary-icon moon" />
            <div className="summary-data">
              <span className="summary-value">10:30 PM</span>
              <span className="summary-label">BEDTIME</span>
            </div>
          </div>
          <div className="summary-item">
            <Sun size={18} className="summary-icon sun" />
            <div className="summary-data">
              <span className="summary-value">7:00 AM</span>
              <span className="summary-label">WAKE TIME</span>
            </div>
          </div>
          <div className="summary-item">
            <Clock size={18} className="summary-icon clock" />
            <div className="summary-data">
              <span className="summary-value">8h 30m</span>
              <span className="summary-label">DURATION</span>
            </div>
          </div>
          <div className="summary-item">
            <BedDouble size={18} className="summary-icon bed" />
            <div className="summary-data">
              <span className="summary-value">1 time</span>
              <span className="summary-label">EXITS</span>
            </div>
          </div>
        </div>
      </div>

      {/* Health Metrics */}
      <div className="data-card metrics-card">
        <div className="metrics-header">
          <Heart size={18} className="metrics-icon" />
          <h3 className="card-title">Health Metrics</h3>
        </div>
        <div className="metrics-grid">
          <div className="metric-item">
            <div className="metric-icon-wrapper heart">
              <Heart size={16} />
            </div>
            <span className="metric-value">{healthMetrics.avgHR}<span className="metric-unit">bpm</span></span>
            <span className="metric-label">Avg HR</span>
          </div>
          <div className="metric-item">
            <div className="metric-icon-wrapper hrv">
              <Activity size={16} />
            </div>
            <span className="metric-value">{healthMetrics.hrv}<span className="metric-unit">ms</span></span>
            <span className="metric-label">HRV</span>
          </div>
          <div className="metric-item">
            <div className="metric-icon-wrapper breath">
              <Wind size={16} />
            </div>
            <span className="metric-value">{healthMetrics.breath}<span className="metric-unit">min</span></span>
            <span className="metric-label">Breath</span>
          </div>
          <div className="metric-item">
            <div className="metric-icon-wrapper min-hr">
              <Droplets size={16} />
            </div>
            <span className="metric-value">{healthMetrics.minHR}<span className="metric-unit">bpm</span></span>
            <span className="metric-label">Min HR</span>
          </div>
          <div className="metric-item">
            <div className="metric-icon-wrapper max-hr">
              <Heart size={16} />
            </div>
            <span className="metric-value">{healthMetrics.maxHR}<span className="metric-unit">bpm</span></span>
            <span className="metric-label">Max HR</span>
          </div>
          <div className="metric-item">
            <div className="metric-icon-wrapper spo2">
              <Droplets size={16} />
            </div>
            <span className="metric-value">{healthMetrics.spo2}<span className="metric-unit">%</span></span>
            <span className="metric-label">SpO2</span>
          </div>
        </div>
      </div>

      {/* Heart Rate Chart */}
      <div className="data-card chart-card">
        <div className="chart-header">
          <div className="chart-title-row">
            <Heart size={18} className="chart-icon heart" />
            <h3 className="card-title">Heart Rate</h3>
          </div>
          <span className="chart-avg">Avg: 55 bpm</span>
        </div>
        <div className="line-chart">
          <svg viewBox="0 0 400 100" className="chart-svg">
            <path
              d="M 0 60 Q 30 45, 60 50 T 120 40 T 180 55 T 240 35 T 300 50 T 360 45 T 400 30"
              fill="none"
              stroke="#e05050"
              strokeWidth="2"
            />
            <line x1="0" y1="55" x2="400" y2="55" stroke="#e05050" strokeWidth="1" strokeDasharray="4" opacity="0.3" />
          </svg>
        </div>
        <div className="chart-info-banner">
          <span className="info-icon">ℹ</span>
          <span>Heart rate data validated with 6 participants. You can help improve accuracy by contributing data.</span>
        </div>
      </div>

      {/* Sleep Stages Timeline */}
      <div className="data-card stages-timeline-card">
        <div className="chart-header">
          <div className="chart-title-row">
            <Activity size={18} className="chart-icon stages" />
            <h3 className="card-title">Sleep Stages</h3>
          </div>
        </div>
        <div className="stages-timeline">
          <div className="stages-y-labels">
            <span>Light</span>
            <span>REM</span>
          </div>
          <svg viewBox="0 0 400 60" className="stages-svg">
            <path
              d="M 0 15 L 30 15 L 30 45 L 60 45 L 60 15 L 90 15 L 90 30 L 120 30 L 120 15 L 150 15 L 150 45 L 180 45 L 180 15 L 210 15 L 210 15 L 240 15 L 240 30 L 270 30 L 270 15 L 300 15 L 300 30 L 330 30 L 330 45 L 360 45 L 360 15 L 400 15"
              fill="none"
              stroke="#9370db"
              strokeWidth="3"
            />
            {/* Fill areas */}
            <path
              d="M 30 45 L 60 45 L 60 60 L 30 60 Z"
              fill="rgba(147, 112, 219, 0.3)"
            />
            <path
              d="M 150 45 L 180 45 L 180 60 L 150 60 Z"
              fill="rgba(147, 112, 219, 0.3)"
            />
            <path
              d="M 330 45 L 360 45 L 360 60 L 330 60 Z"
              fill="rgba(147, 112, 219, 0.3)"
            />
          </svg>
        </div>
        <div className="stages-x-labels">
          <span>11:00</span>
          <span>12:30</span>
          <span>2:00</span>
          <span>3:30</span>
          <span>5:00</span>
          <span>6:30</span>
        </div>
        <div className="stages-legend-row">
          <span className="legend-item"><span className="legend-dot awake" /> Awake</span>
          <span className="legend-item"><span className="legend-dot light" /> Light</span>
          <span className="legend-item"><span className="legend-dot deep" /> Deep</span>
          <span className="legend-item"><span className="legend-dot rem" /> REM</span>
        </div>
      </div>

      {/* Movement */}
      <div className="data-card movement-card">
        <div className="chart-header">
          <div className="chart-title-row">
            <Move size={18} className="chart-icon movement" />
            <h3 className="card-title">Movement</h3>
          </div>
          <span className="chart-avg">Restless: {movementData.restlessMin} min</span>
        </div>
        <div className="movement-stats">
          <div className="movement-stat">
            <span className="movement-value">{movementData.positionChanges}</span>
            <span className="movement-label">Position Changes</span>
          </div>
          <div className="movement-stat">
            <span className="movement-value">{movementData.timeStill}%</span>
            <span className="movement-label">Time Still</span>
          </div>
          <div className="movement-stat">
            <span className="movement-value">{movementData.restlessness}</span>
            <span className="movement-label">Restlessness</span>
          </div>
        </div>
        <div className="movement-chart">
          <svg viewBox="0 0 400 40" className="movement-svg">
            {[...Array(40)].map((_, i) => (
              <rect
                key={i}
                x={i * 10}
                y={40 - Math.random() * 30 - 5}
                width="6"
                height={Math.random() * 30 + 5}
                fill={Math.random() > 0.7 ? '#d4a84a' : '#8b7355'}
                rx="1"
              />
            ))}
          </svg>
        </div>
        <div className="movement-x-labels">
          <span>10:30 PM</span>
          <span>2:00 AM</span>
          <span>5:30 AM</span>
        </div>
      </div>
    </div>
  )
}

export default DataScreen
