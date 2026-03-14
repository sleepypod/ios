import { useState } from 'react'
import { Moon, Sun, Clock, Trash2, Plus, Minus, GripVertical, ChevronDown, ChevronUp, Sliders, Link, Unlink } from 'lucide-react'

type ScheduleVariant = 'blocks' | 'list' | 'timeline' | 'clock' | 'gradient' | 'accordion' | 'dualslider' | 'smartpresets' | 'grid' | 'wedges' | 'accordiongraph' | 'smoothline' | 'stepline'
type SleepProfile = 'cool' | 'balanced' | 'warm'
type SelectedSide = 'left' | 'right' | 'both'

interface ScheduleScreenProps {
  variant: ScheduleVariant
}

interface SleepPhase {
  id: string
  name: string
  startTime: string
  temp: number
  icon: 'moon' | 'sleep' | 'sun'
}

interface TimeSlot {
  id: number
  time: string
  temp: number
}

function ScheduleScreen({ variant }: ScheduleScreenProps) {
  const [selectedDays, setSelectedDays] = useState([0, 1, 2, 3, 4])
  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S']
  const [sleepProfile, setSleepProfile] = useState<SleepProfile>('cool')
  const [scheduleActive, setScheduleActive] = useState(true)
  const [selectedSide, setSelectedSide] = useState<SelectedSide>('left')

  const handleSideSelect = (side: 'left' | 'right') => {
    if (selectedSide === 'both') return // Don't allow switching when linked
    setSelectedSide(side)
  }

  const handleLinkToggle = () => {
    if (selectedSide === 'both') {
      setSelectedSide('left')
    } else {
      setSelectedSide('both')
    }
  }

  // Shared sleep phase data
  const [phases, setPhases] = useState<SleepPhase[]>([
    { id: 'bedtime', name: 'Bedtime', startTime: '10:00 PM', temp: -1, icon: 'moon' },
    { id: 'deep', name: 'Deep Sleep', startTime: '11:30 PM', temp: -3, icon: 'sleep' },
    { id: 'prewake', name: 'Pre-Wake', startTime: '5:30 AM', temp: 0, icon: 'sun' },
    { id: 'wake', name: 'Wake Up', startTime: '7:00 AM', temp: 2, icon: 'sun' },
  ])

  // For list/timeline variants
  const [timeSlots, setTimeSlots] = useState<TimeSlot[]>([
    { id: 1, time: '10:00 PM', temp: -1 },
    { id: 2, time: '11:30 PM', temp: -3 },
    { id: 3, time: '2:00 AM', temp: -2 },
    { id: 4, time: '5:30 AM', temp: 0 },
    { id: 5, time: '7:00 AM', temp: 2 },
  ])

  // For clock variant
  const [clockTemps, setClockTemps] = useState<{ [hour: number]: number }>({
    22: -1, // 10 PM
    23: -2,
    0: -3,
    1: -3,
    2: -2,
    3: -1,
    4: 0,
    5: 1,
    6: 2,
    7: 2,
  })

  // For gradient variant - keyframe points
  const [gradientPoints, setGradientPoints] = useState([
    { id: 1, time: 0, temp: -1 },    // 10PM = 0%
    { id: 2, time: 17, temp: -3 },   // ~11:30PM
    { id: 3, time: 50, temp: -2 },   // ~3AM
    { id: 4, time: 83, temp: 0 },    // ~5:30AM
    { id: 5, time: 100, temp: 2 },   // 7AM = 100%
  ])

  // For accordion variant
  const [expandedPhase, setExpandedPhase] = useState<string | null>('bedtime')

  // For dual slider variant
  const [bedtimeTemp, setBedtimeTemp] = useState(-2)
  const [wakeTemp, setWakeTemp] = useState(2)

  // For smart presets variant
  const [showAdvanced, setShowAdvanced] = useState(false)

  // For grid variant - 30 minute blocks (18 blocks from 10PM to 7AM)
  const [gridTemps, setGridTemps] = useState<number[]>([
    -1, -2, -3, -3, -3, -3, -2, -2, -2, -1, -1, 0, 0, 1, 1, 2, 2, 2
  ])

  // For wedges variant - temperature zones with adjustable boundaries
  const [wedgeZones, setWedgeZones] = useState([
    { id: 'cool', startHour: 22, endHour: 3, temp: -3 },
    { id: 'transition', startHour: 3, endHour: 5, temp: 0 },
    { id: 'warm', startHour: 5, endHour: 7, temp: 2 },
  ])

  // For smoothline/stepline variants - grouped stages (3 main phases like Eight Sleep)
  const [groupedStages, setGroupedStages] = useState([
    { id: 'falling', name: 'Falling Asleep', startTime: '10:00 PM', temp: 0, color: '#a080d0' },
    { id: 'deep', name: 'Deep Sleep', startTime: '11:30 PM', temp: -1, color: '#4a90d9' },
    { id: 'waking', name: 'Waking Up', startTime: '6:00 AM', temp: 2, color: '#e0a050' },
  ])

  const updateGroupedStageTemp = (id: string, delta: number) => {
    setGroupedStages(stages =>
      stages.map(s => s.id === id ? { ...s, temp: Math.max(-10, Math.min(10, s.temp + delta)) } : s)
    )
  }

  const toggleDay = (index: number) => {
    if (selectedDays.includes(index)) {
      setSelectedDays(selectedDays.filter(d => d !== index))
    } else {
      setSelectedDays([...selectedDays, index])
    }
  }

  const updatePhaseTemp = (id: string, delta: number) => {
    setPhases(phases.map(p =>
      p.id === id ? { ...p, temp: Math.max(-10, Math.min(10, p.temp + delta)) } : p
    ))
  }

  const updateSlotTemp = (id: number, delta: number) => {
    setTimeSlots(timeSlots.map(s =>
      s.id === id ? { ...s, temp: Math.max(-10, Math.min(10, s.temp + delta)) } : s
    ))
  }

  const addTimeSlot = () => {
    const newId = Math.max(...timeSlots.map(s => s.id), 0) + 1
    setTimeSlots([...timeSlots, { id: newId, time: '3:00 AM', temp: 0 }])
  }

  const deleteTimeSlot = (id: number) => {
    setTimeSlots(timeSlots.filter(s => s.id !== id))
  }

  const updateClockTemp = (hour: number, delta: number) => {
    setClockTemps(prev => ({
      ...prev,
      [hour]: Math.max(-10, Math.min(10, (prev[hour] || 0) + delta))
    }))
  }

  const updateGradientPoint = (id: number, delta: number) => {
    setGradientPoints(points =>
      points.map(p => p.id === id ? { ...p, temp: Math.max(-10, Math.min(10, p.temp + delta)) } : p)
    )
  }

  const addGradientPoint = () => {
    const newId = Math.max(...gradientPoints.map(p => p.id), 0) + 1
    setGradientPoints([...gradientPoints, { id: newId, time: 50, temp: 0 }].sort((a, b) => a.time - b.time))
  }

  const removeGradientPoint = (id: number) => {
    if (gradientPoints.length > 2) {
      setGradientPoints(gradientPoints.filter(p => p.id !== id))
    }
  }

  const updateGridTemp = (index: number) => {
    setGridTemps(temps => {
      const newTemps = [...temps]
      // Cycle through: -3 -> -2 -> -1 -> 0 -> 1 -> 2 -> 3 -> -3
      newTemps[index] = newTemps[index] >= 3 ? -3 : newTemps[index] + 1
      return newTemps
    })
  }

  const getGridTempColor = (temp: number) => {
    if (temp <= -2) return '#2563eb'  // Deep blue
    if (temp === -1) return '#60a5fa' // Light blue
    if (temp === 0) return '#6b7280'  // Gray
    if (temp === 1) return '#fb923c'  // Light orange
    return '#dc2626'                   // Red/warm
  }

  const getTempColor = (temp: number) => {
    if (temp < 0) return '#4a90d9'
    if (temp > 0) return '#dc6646'
    return '#888'
  }

  // ============ VARIANT 1: TIME BLOCKS ============
  const renderBlocksVariant = () => (
    <div className="schedule-variant blocks-variant">
      <div className="variant-header">
        <span className="variant-title">Sleep Phases</span>
        <span className="variant-subtitle">Tap a phase to adjust temperature</span>
      </div>

      <div className="phase-blocks">
        {phases.map((phase, index) => (
          <div key={phase.id} className="phase-block">
            <div className="phase-connector">
              {index > 0 && <div className="connector-line" />}
              <div className="phase-dot" style={{ background: getTempColor(phase.temp) }} />
              {index < phases.length - 1 && <div className="connector-line" />}
            </div>
            <div className="phase-content">
              <div className="phase-header">
                <span className="phase-icon">
                  {phase.icon === 'moon' ? <Moon size={16} /> : phase.icon === 'sleep' ? '💤' : <Sun size={16} />}
                </span>
                <span className="phase-name">{phase.name}</span>
                <span className="phase-time">{phase.startTime}</span>
              </div>
              <div className="phase-temp-control">
                <button className="phase-temp-btn" onClick={() => updatePhaseTemp(phase.id, -1)}>
                  <Minus size={14} />
                </button>
                <span className="phase-temp" style={{ color: getTempColor(phase.temp) }}>
                  {phase.temp > 0 ? '+' : ''}{phase.temp}
                </span>
                <button className="phase-temp-btn" onClick={() => updatePhaseTemp(phase.id, 1)}>
                  <Plus size={14} />
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )

  // ============ VARIANT 2: VERTICAL LIST ============
  const renderListVariant = () => (
    <div className="schedule-variant list-variant">
      <div className="variant-header">
        <span className="variant-title">Temperature Schedule</span>
        <button className="add-slot-btn" onClick={addTimeSlot}>
          <Plus size={16} />
          <span>Add</span>
        </button>
      </div>

      <div className="time-slots-list">
        {timeSlots.map((slot) => (
          <div key={slot.id} className="time-slot-row">
            <div className="slot-grip">
              <GripVertical size={16} />
            </div>
            <div className="slot-time">
              <Clock size={14} />
              <span>{slot.time}</span>
            </div>
            <div className="slot-temp-control">
              <button className="slot-temp-btn" onClick={() => updateSlotTemp(slot.id, -1)}>
                <Minus size={12} />
              </button>
              <span className="slot-temp" style={{ color: getTempColor(slot.temp) }}>
                {slot.temp > 0 ? '+' : ''}{slot.temp}
              </span>
              <button className="slot-temp-btn" onClick={() => updateSlotTemp(slot.id, 1)}>
                <Plus size={12} />
              </button>
            </div>
            <button className="slot-delete" onClick={() => deleteTimeSlot(slot.id)}>
              <Trash2 size={14} />
            </button>
          </div>
        ))}
      </div>
    </div>
  )

  // ============ VARIANT 3: TIMELINE WITH HANDLES ============
  const renderTimelineVariant = () => {
    const timelineHours = ['10PM', '11PM', '12AM', '1AM', '2AM', '3AM', '4AM', '5AM', '6AM', '7AM']

    return (
      <div className="schedule-variant timeline-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Timeline</span>
          <span className="variant-subtitle">Drag handles to adjust</span>
        </div>

        <div className="timeline-container">
          {/* Temperature scale on left */}
          <div className="timeline-scale">
            <span>+3</span>
            <span>0</span>
            <span>-3</span>
          </div>

          {/* Timeline graph */}
          <div className="timeline-graph">
            {/* Hour markers */}
            <div className="timeline-hours">
              {timelineHours.map((hour, i) => (
                <span key={i} className="timeline-hour">{hour}</span>
              ))}
            </div>

            {/* SVG curve with handles */}
            <div className="timeline-curve-area">
              <svg viewBox="0 0 360 100" className="timeline-svg">
                {/* Grid lines */}
                <line x1="0" y1="50" x2="360" y2="50" stroke="#333" strokeDasharray="2 2" />
                <line x1="0" y1="25" x2="360" y2="25" stroke="#222" strokeDasharray="2 2" />
                <line x1="0" y1="75" x2="360" y2="75" stroke="#222" strokeDasharray="2 2" />

                {/* Temperature curve */}
                <path
                  d="M 0 55 L 40 65 L 80 80 L 120 80 L 160 70 L 200 60 L 240 50 L 280 40 L 320 30 L 360 30"
                  fill="none"
                  stroke="#4a90d9"
                  strokeWidth="2"
                />

                {/* Draggable handles */}
                {timeSlots.map((slot, i) => {
                  const x = (i / (timeSlots.length - 1)) * 360
                  const y = 50 - (slot.temp * 8)
                  return (
                    <g key={slot.id} className="timeline-handle">
                      <circle cx={x} cy={y} r="8" fill={getTempColor(slot.temp)} />
                      <text x={x} y={y + 4} textAnchor="middle" fill="#fff" fontSize="10">
                        {slot.temp > 0 ? '+' : ''}{slot.temp}
                      </text>
                    </g>
                  )
                })}
              </svg>
            </div>

            {/* Quick adjust buttons */}
            <div className="timeline-quick-adjust">
              {timeSlots.slice(0, 5).map((slot) => (
                <div key={slot.id} className="quick-adjust-group">
                  <button onClick={() => updateSlotTemp(slot.id, 1)}>+</button>
                  <button onClick={() => updateSlotTemp(slot.id, -1)}>−</button>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 4: CIRCULAR CLOCK ============
  const renderClockVariant = () => {
    const clockHours = [22, 23, 0, 1, 2, 3, 4, 5, 6, 7] // 10PM to 7AM
    const hourLabels = ['10', '11', '12', '1', '2', '3', '4', '5', '6', '7']

    return (
      <div className="schedule-variant clock-variant">
        <div className="variant-header">
          <span className="variant-title">Night Clock</span>
          <span className="variant-subtitle">Tap segments to adjust temp</span>
        </div>

        <div className="clock-container">
          <svg viewBox="0 0 200 200" className="clock-svg">
            {/* Clock face background */}
            <circle cx="100" cy="100" r="90" fill="#1a1a2e" stroke="#333" strokeWidth="2" />

            {/* Hour segments as arcs */}
            {clockHours.map((hour, i) => {
              const temp = clockTemps[hour] || 0
              const startAngle = -90 + (i * 36) // 360/10 = 36 degrees per hour
              const endAngle = startAngle + 36
              const startRad = (startAngle * Math.PI) / 180
              const endRad = (endAngle * Math.PI) / 180
              const innerR = 45
              const outerR = 80

              const x1 = 100 + innerR * Math.cos(startRad)
              const y1 = 100 + innerR * Math.sin(startRad)
              const x2 = 100 + outerR * Math.cos(startRad)
              const y2 = 100 + outerR * Math.sin(startRad)
              const x3 = 100 + outerR * Math.cos(endRad)
              const y3 = 100 + outerR * Math.sin(endRad)
              const x4 = 100 + innerR * Math.cos(endRad)
              const y4 = 100 + innerR * Math.sin(endRad)

              return (
                <g key={hour} className="clock-segment" onClick={() => updateClockTemp(hour, 1)}>
                  <path
                    d={`M ${x1} ${y1} L ${x2} ${y2} A ${outerR} ${outerR} 0 0 1 ${x3} ${y3} L ${x4} ${y4} A ${innerR} ${innerR} 0 0 0 ${x1} ${y1}`}
                    fill={getTempColor(temp)}
                    opacity={0.3 + Math.abs(temp) * 0.07}
                    stroke="#333"
                    strokeWidth="1"
                    style={{ cursor: 'pointer' }}
                  />
                  <text
                    x={100 + 62 * Math.cos((startRad + endRad) / 2)}
                    y={100 + 62 * Math.sin((startRad + endRad) / 2) + 4}
                    textAnchor="middle"
                    fill="#fff"
                    fontSize="10"
                    fontWeight="500"
                  >
                    {temp > 0 ? '+' : ''}{temp}
                  </text>
                </g>
              )
            })}

            {/* Hour labels around outside */}
            {hourLabels.map((label, i) => {
              const angle = -90 + (i * 36) + 18 // Center of each segment
              const rad = (angle * Math.PI) / 180
              return (
                <text
                  key={i}
                  x={100 + 88 * Math.cos(rad)}
                  y={100 + 88 * Math.sin(rad) + 3}
                  textAnchor="middle"
                  fill="#666"
                  fontSize="8"
                >
                  {label}
                </text>
              )
            })}

            {/* Center label */}
            <text x="100" y="95" textAnchor="middle" fill="#888" fontSize="10">TAP TO</text>
            <text x="100" y="108" textAnchor="middle" fill="#888" fontSize="10">ADJUST</text>
          </svg>

          {/* Legend */}
          <div className="clock-legend">
            <div className="legend-item">
              <span className="legend-dot cool" />
              <span>Cool</span>
            </div>
            <div className="legend-item">
              <span className="legend-dot neutral" />
              <span>Neutral</span>
            </div>
            <div className="legend-item">
              <span className="legend-dot warm" />
              <span>Warm</span>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 5: GRADIENT BAR ============
  const renderGradientVariant = () => {
    // Build gradient string from points
    const sortedPoints = [...gradientPoints].sort((a, b) => a.time - b.time)
    const gradientStops = sortedPoints.map(p =>
      `${getTempColor(p.temp)} ${p.time}%`
    ).join(', ')

    return (
      <div className="schedule-variant gradient-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Gradient</span>
          <button className="add-point-btn" onClick={addGradientPoint}>
            <Plus size={14} />
            <span>Add Point</span>
          </button>
        </div>

        {/* Gradient bar with keyframes */}
        <div className="gradient-container">
          <div className="gradient-time-labels">
            <span>10PM</span>
            <span>1AM</span>
            <span>4AM</span>
            <span>7AM</span>
          </div>

          <div
            className="gradient-bar"
            style={{ background: `linear-gradient(to right, ${gradientStops})` }}
          >
            {sortedPoints.map((point) => (
              <div
                key={point.id}
                className="gradient-keyframe"
                style={{ left: `${point.time}%` }}
              >
                <div className="keyframe-marker" style={{ background: getTempColor(point.temp) }}>
                  <span className="keyframe-temp">
                    {point.temp > 0 ? '+' : ''}{point.temp}
                  </span>
                </div>
                <div className="keyframe-controls">
                  <button onClick={() => updateGradientPoint(point.id, 1)}><Plus size={10} /></button>
                  <button onClick={() => updateGradientPoint(point.id, -1)}><Minus size={10} /></button>
                  {gradientPoints.length > 2 && (
                    <button onClick={() => removeGradientPoint(point.id)} className="keyframe-delete">
                      <Trash2 size={10} />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>

          <div className="gradient-hint">Tap +/- to adjust temperature at each point</div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 6: STACKED CARDS / ACCORDION ============
  const renderAccordionVariant = () => (
    <div className="schedule-variant accordion-variant">
      <div className="variant-header">
        <span className="variant-title">Sleep Segments</span>
        <span className="variant-subtitle">Expand to adjust</span>
      </div>

      <div className="accordion-list">
        {phases.map((phase) => (
          <div key={phase.id} className={`accordion-item ${expandedPhase === phase.id ? 'expanded' : ''}`}>
            <button
              className="accordion-header"
              onClick={() => setExpandedPhase(expandedPhase === phase.id ? null : phase.id)}
            >
              <div className="accordion-header-left">
                <span className="phase-icon">
                  {phase.icon === 'moon' ? <Moon size={16} /> : phase.icon === 'sleep' ? '💤' : <Sun size={16} />}
                </span>
                <span className="accordion-phase-name">{phase.name}</span>
              </div>
              <div className="accordion-header-right">
                <span className="accordion-temp" style={{ color: getTempColor(phase.temp) }}>
                  {phase.temp > 0 ? '+' : ''}{phase.temp}
                </span>
                <span className="accordion-time">{phase.startTime}</span>
                {expandedPhase === phase.id ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
              </div>
            </button>

            {expandedPhase === phase.id && (
              <div className="accordion-content">
                <div className="accordion-slider-row">
                  <span className="slider-label">Temperature</span>
                  <div className="accordion-temp-slider">
                    <button onClick={() => updatePhaseTemp(phase.id, -1)}><Minus size={14} /></button>
                    <input
                      type="range"
                      min="-10"
                      max="10"
                      value={phase.temp}
                      onChange={(e) => {
                        const newTemp = parseInt(e.target.value)
                        setPhases(phases.map(p => p.id === phase.id ? { ...p, temp: newTemp } : p))
                      }}
                      className="temp-slider"
                    />
                    <button onClick={() => updatePhaseTemp(phase.id, 1)}><Plus size={14} /></button>
                  </div>
                </div>
                <div className="accordion-time-row">
                  <span className="slider-label">Start Time</span>
                  <span className="time-display">{phase.startTime}</span>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )

  // ============ VARIANT 7: DUAL-AXIS SLIDER ============
  const renderDualSliderVariant = () => {
    // Calculate intermediate points for the curve
    const midTemp = Math.round((bedtimeTemp + wakeTemp) / 2)

    return (
      <div className="schedule-variant dualslider-variant">
        <div className="variant-header">
          <span className="variant-title">Simple Schedule</span>
          <span className="variant-subtitle">Set start and end temps</span>
        </div>

        <div className="dualslider-container">
          {/* Bedtime slider */}
          <div className="temp-slider-column">
            <span className="slider-time">10 PM</span>
            <span className="slider-time-label">BEDTIME</span>
            <div className="vertical-slider-container">
              <div className="vertical-slider-track">
                <div
                  className="vertical-slider-fill"
                  style={{
                    height: `${((bedtimeTemp + 10) / 20) * 100}%`,
                    background: getTempColor(bedtimeTemp)
                  }}
                />
                <div
                  className="vertical-slider-thumb"
                  style={{ bottom: `${((bedtimeTemp + 10) / 20) * 100}%` }}
                />
              </div>
              <div className="slider-buttons">
                <button onClick={() => setBedtimeTemp(Math.min(10, bedtimeTemp + 1))}><Plus size={14} /></button>
                <span className="slider-value" style={{ color: getTempColor(bedtimeTemp) }}>
                  {bedtimeTemp > 0 ? '+' : ''}{bedtimeTemp}
                </span>
                <button onClick={() => setBedtimeTemp(Math.max(-10, bedtimeTemp - 1))}><Minus size={14} /></button>
              </div>
            </div>
          </div>

          {/* Curve visualization */}
          <div className="curve-preview">
            <svg viewBox="0 0 100 80" className="curve-svg-small">
              <defs>
                <linearGradient id="curveGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" stopColor={getTempColor(bedtimeTemp)} />
                  <stop offset="50%" stopColor={getTempColor(midTemp)} />
                  <stop offset="100%" stopColor={getTempColor(wakeTemp)} />
                </linearGradient>
              </defs>
              <path
                d={`M 0 ${40 - bedtimeTemp * 3} Q 50 ${40 - midTemp * 3 - 10} 100 ${40 - wakeTemp * 3}`}
                fill="none"
                stroke="url(#curveGradient)"
                strokeWidth="3"
              />
              <circle cx="0" cy={40 - bedtimeTemp * 3} r="4" fill={getTempColor(bedtimeTemp)} />
              <circle cx="100" cy={40 - wakeTemp * 3} r="4" fill={getTempColor(wakeTemp)} />
            </svg>
            <span className="curve-label">Auto-generated curve</span>
          </div>

          {/* Wake slider */}
          <div className="temp-slider-column">
            <span className="slider-time">7 AM</span>
            <span className="slider-time-label">WAKE UP</span>
            <div className="vertical-slider-container">
              <div className="vertical-slider-track">
                <div
                  className="vertical-slider-fill"
                  style={{
                    height: `${((wakeTemp + 10) / 20) * 100}%`,
                    background: getTempColor(wakeTemp)
                  }}
                />
                <div
                  className="vertical-slider-thumb"
                  style={{ bottom: `${((wakeTemp + 10) / 20) * 100}%` }}
                />
              </div>
              <div className="slider-buttons">
                <button onClick={() => setWakeTemp(Math.min(10, wakeTemp + 1))}><Plus size={14} /></button>
                <span className="slider-value" style={{ color: getTempColor(wakeTemp) }}>
                  {wakeTemp > 0 ? '+' : ''}{wakeTemp}
                </span>
                <button onClick={() => setWakeTemp(Math.max(-10, wakeTemp - 1))}><Minus size={14} /></button>
              </div>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 8: SMART PRESETS + OVERRIDE ============
  const renderSmartPresetsVariant = () => (
    <div className="schedule-variant smartpresets-variant">
      <div className="variant-header">
        <span className="variant-title">Quick Setup</span>
        <span className="variant-subtitle">Choose a profile</span>
      </div>

      {/* Large preset cards */}
      <div className="preset-cards">
        <button
          className={`preset-card ${sleepProfile === 'cool' ? 'active' : ''}`}
          onClick={() => setSleepProfile('cool')}
        >
          <div className="preset-icon cool">❄️</div>
          <span className="preset-name">Cool Sleeper</span>
          <span className="preset-desc">Stays cool all night</span>
          <div className="preset-preview">
            <span className="preview-temp cool">-3</span>
            <span className="preview-arrow">→</span>
            <span className="preview-temp cool">-1</span>
          </div>
        </button>

        <button
          className={`preset-card ${sleepProfile === 'balanced' ? 'active' : ''}`}
          onClick={() => setSleepProfile('balanced')}
        >
          <div className="preset-icon balanced">⚖️</div>
          <span className="preset-name">Balanced</span>
          <span className="preset-desc">Science-backed curve</span>
          <div className="preset-preview">
            <span className="preview-temp cool">-2</span>
            <span className="preview-arrow">→</span>
            <span className="preview-temp warm">+2</span>
          </div>
        </button>

        <button
          className={`preset-card ${sleepProfile === 'warm' ? 'active' : ''}`}
          onClick={() => setSleepProfile('warm')}
        >
          <div className="preset-icon warm">🔥</div>
          <span className="preset-name">Warm Sleeper</span>
          <span className="preset-desc">Cozy and warm</span>
          <div className="preset-preview">
            <span className="preview-temp warm">+1</span>
            <span className="preview-arrow">→</span>
            <span className="preview-temp warm">+3</span>
          </div>
        </button>
      </div>

      {/* Advanced toggle */}
      <button
        className="advanced-toggle"
        onClick={() => setShowAdvanced(!showAdvanced)}
      >
        <Sliders size={16} />
        <span>{showAdvanced ? 'Hide' : 'Show'} Advanced</span>
        {showAdvanced ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
      </button>

      {/* Advanced mini-graph */}
      {showAdvanced && (
        <div className="advanced-panel">
          <div className="mini-graph">
            <svg viewBox="0 0 200 60" className="mini-graph-svg">
              <line x1="0" y1="30" x2="200" y2="30" stroke="#333" strokeDasharray="2" />
              {timeSlots.slice(0, 4).map((slot, i) => {
                const x = (i / 3) * 200
                const y = 30 - slot.temp * 5
                return (
                  <g key={slot.id}>
                    <circle cx={x} cy={y} r="8" fill={getTempColor(slot.temp)} />
                    <text x={x} y={y + 4} textAnchor="middle" fill="#fff" fontSize="9">
                      {slot.temp > 0 ? '+' : ''}{slot.temp}
                    </text>
                  </g>
                )
              })}
              <path
                d={`M 0 ${30 - timeSlots[0].temp * 5} ${timeSlots.slice(0, 4).map((s, i) =>
                  `L ${(i / 3) * 200} ${30 - s.temp * 5}`
                ).join(' ')}`}
                fill="none"
                stroke="#4a90d9"
                strokeWidth="2"
              />
            </svg>
          </div>
          <div className="mini-graph-controls">
            {timeSlots.slice(0, 4).map((slot) => (
              <div key={slot.id} className="mini-control">
                <button onClick={() => updateSlotTemp(slot.id, 1)}><Plus size={12} /></button>
                <button onClick={() => updateSlotTemp(slot.id, -1)}><Minus size={12} /></button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )

  // ============ VARIANT 9: TIME-BLOCK GRID ============
  const renderGridVariant = () => {
    const timeLabels = ['10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '1:00', '1:30', '2:00',
                        '2:30', '3:00', '3:30', '4:00', '4:30', '5:00', '5:30', '6:00', '6:30']

    return (
      <div className="schedule-variant grid-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Grid</span>
          <span className="variant-subtitle">Tap cells to cycle temp</span>
        </div>

        <div className="grid-container">
          {/* Color legend */}
          <div className="grid-legend">
            <div className="legend-item"><span className="legend-swatch" style={{ background: '#2563eb' }} />-3</div>
            <div className="legend-item"><span className="legend-swatch" style={{ background: '#60a5fa' }} />-1</div>
            <div className="legend-item"><span className="legend-swatch" style={{ background: '#6b7280' }} />0</div>
            <div className="legend-item"><span className="legend-swatch" style={{ background: '#fb923c' }} />+1</div>
            <div className="legend-item"><span className="legend-swatch" style={{ background: '#dc2626' }} />+3</div>
          </div>

          {/* Grid cells */}
          <div className="temp-grid">
            {gridTemps.map((temp, index) => (
              <button
                key={index}
                className="grid-cell"
                style={{ background: getGridTempColor(temp) }}
                onClick={() => updateGridTemp(index)}
              >
                <span className="grid-cell-time">{timeLabels[index]}</span>
                <span className="grid-cell-temp">{temp > 0 ? '+' : ''}{temp}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 10: CIRCULAR CLOCK WITH DRAGGABLE WEDGES ============
  const renderWedgesVariant = () => {
    const zones = [
      { label: 'Cool Zone', color: '#4a90d9', temp: -3 },
      { label: 'Transition', color: '#888', temp: 0 },
      { label: 'Warm Zone', color: '#dc6646', temp: 2 },
    ]

    return (
      <div className="schedule-variant wedges-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Zones</span>
          <span className="variant-subtitle">Adjust zone boundaries</span>
        </div>

        <div className="wedges-container">
          <svg viewBox="0 0 200 200" className="wedges-svg">
            {/* Background circle */}
            <circle cx="100" cy="100" r="90" fill="#1a1a2e" stroke="#333" strokeWidth="2" />

            {/* Cool zone (10PM - 3AM) = ~55% of night */}
            <path
              d={`M 100 100 L 100 10 A 90 90 0 0 1 ${100 + 90 * Math.cos(-90 * Math.PI / 180 + (5/9) * Math.PI * 2)} ${100 + 90 * Math.sin(-90 * Math.PI / 180 + (5/9) * Math.PI * 2)} Z`}
              fill="#4a90d9"
              opacity="0.5"
            />

            {/* Transition zone (3AM - 5AM) = ~22% of night */}
            <path
              d={`M 100 100 L ${100 + 90 * Math.cos(-90 * Math.PI / 180 + (5/9) * Math.PI * 2)} ${100 + 90 * Math.sin(-90 * Math.PI / 180 + (5/9) * Math.PI * 2)} A 90 90 0 0 1 ${100 + 90 * Math.cos(-90 * Math.PI / 180 + (7/9) * Math.PI * 2)} ${100 + 90 * Math.sin(-90 * Math.PI / 180 + (7/9) * Math.PI * 2)} Z`}
              fill="#888"
              opacity="0.5"
            />

            {/* Warm zone (5AM - 7AM) = ~22% of night */}
            <path
              d={`M 100 100 L ${100 + 90 * Math.cos(-90 * Math.PI / 180 + (7/9) * Math.PI * 2)} ${100 + 90 * Math.sin(-90 * Math.PI / 180 + (7/9) * Math.PI * 2)} A 90 90 0 0 1 100 10 Z`}
              fill="#dc6646"
              opacity="0.5"
            />

            {/* Hour markers */}
            {['10', '11', '12', '1', '2', '3', '4', '5', '6', '7'].map((hour, i) => {
              const angle = -90 + (i * 36) + 18
              const rad = (angle * Math.PI) / 180
              return (
                <text
                  key={i}
                  x={100 + 75 * Math.cos(rad)}
                  y={100 + 75 * Math.sin(rad) + 3}
                  textAnchor="middle"
                  fill="#fff"
                  fontSize="10"
                  fontWeight="500"
                >
                  {hour}
                </text>
              )
            })}

            {/* Center text */}
            <text x="100" y="100" textAnchor="middle" fill="#666" fontSize="10">DRAG</text>
            <text x="100" y="112" textAnchor="middle" fill="#666" fontSize="10">EDGES</text>
          </svg>

          {/* Zone controls */}
          <div className="zone-controls">
            {zones.map((zone, i) => (
              <div key={i} className="zone-control">
                <div className="zone-color" style={{ background: zone.color }} />
                <span className="zone-label">{zone.label}</span>
                <div className="zone-temp-control">
                  <button onClick={() => {/* TODO: adjust zone temp */}}><Minus size={12} /></button>
                  <span style={{ color: zone.color }}>{zone.temp > 0 ? '+' : ''}{zone.temp}</span>
                  <button onClick={() => {/* TODO: adjust zone temp */}}><Plus size={12} /></button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    )
  }

  // ============ VARIANT 11: ACCORDION WITH GRAPH ============
  const renderAccordionGraphVariant = () => {
    // Build SVG path from phases
    const phasePositions = phases.map((phase, index) => ({
      x: (index / (phases.length - 1)) * 100,
      y: 50 - phase.temp * 4,
      temp: phase.temp
    }))

    const pathD = phasePositions.map((p, i) =>
      `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`
    ).join(' ')

    // Create smooth curve path using quadratic bezier
    const smoothPath = phasePositions.reduce((acc, p, i, arr) => {
      if (i === 0) return `M ${p.x} ${p.y}`
      const prev = arr[i - 1]
      const cpX = (prev.x + p.x) / 2
      return `${acc} Q ${cpX} ${prev.y} ${cpX} ${(prev.y + p.y) / 2} T ${p.x} ${p.y}`
    }, '')

    return (
      <div className="schedule-variant accordiongraph-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Schedule</span>
          <span className="variant-subtitle">Visual overview + details</span>
        </div>

        {/* Graph Visualization */}
        <div className="accordiongraph-chart">
          <svg viewBox="0 0 100 100" className="accordiongraph-svg" preserveAspectRatio="none">
            {/* Background gradient */}
            <defs>
              <linearGradient id="agChartGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                {phasePositions.map((p, i) => (
                  <stop
                    key={i}
                    offset={`${p.x}%`}
                    stopColor={getTempColor(p.temp)}
                    stopOpacity="0.3"
                  />
                ))}
              </linearGradient>
              <linearGradient id="agLineGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                {phasePositions.map((p, i) => (
                  <stop
                    key={i}
                    offset={`${p.x}%`}
                    stopColor={getTempColor(p.temp)}
                  />
                ))}
              </linearGradient>
            </defs>

            {/* Grid lines */}
            <line x1="0" y1="50" x2="100" y2="50" stroke="#333" strokeDasharray="2 2" strokeWidth="0.5" />
            <line x1="0" y1="25" x2="100" y2="25" stroke="#222" strokeDasharray="1 2" strokeWidth="0.3" />
            <line x1="0" y1="75" x2="100" y2="75" stroke="#222" strokeDasharray="1 2" strokeWidth="0.3" />

            {/* Area fill under curve */}
            <path
              d={`${pathD} L 100 90 L 0 90 Z`}
              fill="url(#agChartGradient)"
            />

            {/* Main curve line */}
            <path
              d={pathD}
              fill="none"
              stroke="url(#agLineGradient)"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />

            {/* Data points */}
            {phasePositions.map((p, i) => (
              <g key={i}>
                <circle
                  cx={p.x}
                  cy={p.y}
                  r="3"
                  fill={getTempColor(p.temp)}
                  stroke="#0a0a0a"
                  strokeWidth="1"
                />
              </g>
            ))}
          </svg>

          {/* Time labels below graph */}
          <div className="accordiongraph-time-labels">
            {phases.map((phase) => (
              <span key={phase.id}>{phase.startTime.replace(':00', '')}</span>
            ))}
          </div>
        </div>

        {/* Accordion cards */}
        <div className="accordiongraph-list">
          {phases.map((phase, index) => (
            <div
              key={phase.id}
              className={`accordiongraph-item ${expandedPhase === phase.id ? 'expanded' : ''}`}
              style={{ '--phase-color': getTempColor(phase.temp) } as React.CSSProperties}
            >
              <button
                className="accordiongraph-header"
                onClick={() => setExpandedPhase(expandedPhase === phase.id ? null : phase.id)}
              >
                <div className="accordiongraph-indicator" style={{ background: getTempColor(phase.temp) }} />
                <div className="accordiongraph-header-content">
                  <div className="accordiongraph-header-left">
                    <span className="phase-icon">
                      {phase.icon === 'moon' ? <Moon size={14} /> : phase.icon === 'sleep' ? '💤' : <Sun size={14} />}
                    </span>
                    <span className="accordiongraph-phase-name">{phase.name}</span>
                  </div>
                  <div className="accordiongraph-header-right">
                    <span className="accordiongraph-temp" style={{ color: getTempColor(phase.temp) }}>
                      {phase.temp > 0 ? '+' : ''}{phase.temp}
                    </span>
                    <span className="accordiongraph-time">{phase.startTime}</span>
                    {expandedPhase === phase.id ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                  </div>
                </div>
              </button>

              {expandedPhase === phase.id && (
                <div className="accordiongraph-content">
                  <div className="accordiongraph-temp-control">
                    <span className="control-label">Temperature Level</span>
                    <div className="accordiongraph-temp-row">
                      <button
                        className="accordiongraph-btn"
                        onClick={() => updatePhaseTemp(phase.id, -1)}
                      >
                        <Minus size={14} />
                      </button>
                      <div className="accordiongraph-temp-display">
                        <span className="temp-big" style={{ color: getTempColor(phase.temp) }}>
                          {phase.temp > 0 ? '+' : ''}{phase.temp}
                        </span>
                        <span className="temp-range">
                          {phase.temp < 0 ? 'Cooling' : phase.temp > 0 ? 'Heating' : 'Neutral'}
                        </span>
                      </div>
                      <button
                        className="accordiongraph-btn"
                        onClick={() => updatePhaseTemp(phase.id, 1)}
                      >
                        <Plus size={14} />
                      </button>
                    </div>
                  </div>

                  <div className="accordiongraph-temp-bar">
                    <div className="temp-bar-track">
                      <div
                        className="temp-bar-fill"
                        style={{
                          width: `${((phase.temp + 10) / 20) * 100}%`,
                          background: `linear-gradient(to right, #4a90d9, ${getTempColor(phase.temp)})`
                        }}
                      />
                      <div
                        className="temp-bar-marker"
                        style={{ left: `${((phase.temp + 10) / 20) * 100}%` }}
                      />
                    </div>
                    <div className="temp-bar-labels">
                      <span>-10</span>
                      <span>0</span>
                      <span>+10</span>
                    </div>
                  </div>

                  {index < phases.length - 1 && (
                    <div className="accordiongraph-duration">
                      <Clock size={12} />
                      <span>Duration until next phase</span>
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    )
  }

  // ============ VARIANT 12: SMOOTH LINE (like Eight Sleep) ============
  const renderSmoothLineVariant = () => {
    // Calculate positions for the smooth curve (percentage across the night 10PM-7AM = 9 hours)
    const getTimePercent = (time: string) => {
      const [hourStr, period] = time.split(' ')
      const [h] = hourStr.split(':').map(Number)
      let hour = h
      if (period === 'PM' && h !== 12) hour += 12
      if (period === 'AM' && h === 12) hour = 0
      // 10PM = 22, 7AM = 7. Night spans 22->7 (9 hours)
      // Convert to 0-100%
      if (hour >= 22) return ((hour - 22) / 9) * 100
      return ((hour + 2) / 9) * 100 // +2 because 0 is 2 hours after 22
    }

    const stagePositions = groupedStages.map(stage => ({
      ...stage,
      x: getTimePercent(stage.startTime),
      y: 50 - stage.temp * 4
    }))

    // Build smooth bezier curve path
    const buildSmoothPath = () => {
      if (stagePositions.length < 2) return ''
      let path = `M ${stagePositions[0].x} ${stagePositions[0].y}`

      for (let i = 1; i < stagePositions.length; i++) {
        const prev = stagePositions[i - 1]
        const curr = stagePositions[i]
        const cpX = (prev.x + curr.x) / 2
        path += ` C ${cpX} ${prev.y} ${cpX} ${curr.y} ${curr.x} ${curr.y}`
      }
      // Extend to end
      const last = stagePositions[stagePositions.length - 1]
      path += ` C ${(last.x + 100) / 2} ${last.y} 100 ${last.y} 100 ${last.y}`
      return path
    }

    return (
      <div className="schedule-variant smoothline-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Curve</span>
        </div>

        {/* Main curve visualization */}
        <div className="smoothline-chart">
          <svg viewBox="0 0 100 100" className="smoothline-svg" preserveAspectRatio="none">
            <defs>
              {/* Gradient for the line */}
              <linearGradient id="smoothLineGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                {stagePositions.map((s, i) => (
                  <stop key={i} offset={`${s.x}%`} stopColor={s.color} />
                ))}
                <stop offset="100%" stopColor={stagePositions[stagePositions.length - 1].color} />
              </linearGradient>
            </defs>

            {/* Grid line at neutral */}
            <line x1="0" y1="50" x2="100" y2="50" stroke="#333" strokeWidth="0.3" strokeDasharray="2 2" />

            {/* Ghost line showing the path */}
            <path
              d={buildSmoothPath()}
              fill="none"
              stroke="#333"
              strokeWidth="1.5"
              strokeLinecap="round"
            />

            {/* Colored smooth curve */}
            <path
              d={buildSmoothPath()}
              fill="none"
              stroke="url(#smoothLineGrad)"
              strokeWidth="3"
              strokeLinecap="round"
            />

            {/* Draggable handles */}
            {stagePositions.map((stage, i) => (
              <g key={stage.id} className="smoothline-handle">
                <ellipse
                  cx={stage.x}
                  cy={stage.y}
                  rx="4"
                  ry="6"
                  fill={stage.color}
                  stroke="#0a0a0a"
                  strokeWidth="1.5"
                />
              </g>
            ))}
          </svg>
        </div>

        {/* Stage controls below - like Eight Sleep layout */}
        <div className="smoothline-stages">
          {groupedStages.map((stage, index) => (
            <div key={stage.id} className="smoothline-stage">
              <div className="stage-temp" style={{ color: stage.color }}>
                {stage.temp > 0 ? '+' : ''}{stage.temp}
              </div>
              <div
                className="stage-bar"
                style={{
                  background: stage.color,
                  flex: index === groupedStages.length - 1 ? 1 : 'none',
                  width: index === groupedStages.length - 1 ? 'auto' : `${index === 0 ? 35 : 30}%`
                }}
              />
              <div className="stage-info">
                <span className="stage-name">{stage.name.toUpperCase()}</span>
                <span className="stage-time">{stage.startTime}</span>
              </div>
              <div className="stage-controls">
                <button onClick={() => updateGroupedStageTemp(stage.id, -1)}><Minus size={12} /></button>
                <button onClick={() => updateGroupedStageTemp(stage.id, 1)}><Plus size={12} /></button>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  // ============ VARIANT 13: STEP LINE ============
  const renderStepLineVariant = () => {
    // Calculate positions for the step function
    const getTimePercent = (time: string) => {
      const [hourStr, period] = time.split(' ')
      const [h] = hourStr.split(':').map(Number)
      let hour = h
      if (period === 'PM' && h !== 12) hour += 12
      if (period === 'AM' && h === 12) hour = 0
      if (hour >= 22) return ((hour - 22) / 9) * 100
      return ((hour + 2) / 9) * 100
    }

    const stagePositions = groupedStages.map((stage, index) => ({
      ...stage,
      x: getTimePercent(stage.startTime),
      y: 50 - stage.temp * 4,
      // Width extends to next stage or end
      width: index < groupedStages.length - 1
        ? getTimePercent(groupedStages[index + 1].startTime) - getTimePercent(stage.startTime)
        : 100 - getTimePercent(stage.startTime)
    }))

    // Build step path
    const buildStepPath = () => {
      if (stagePositions.length < 1) return ''
      let path = `M 0 ${stagePositions[0].y}`

      stagePositions.forEach((stage, i) => {
        // Horizontal line at this temp
        const nextX = i < stagePositions.length - 1 ? stagePositions[i + 1].x : 100
        path += ` L ${stage.x} ${stage.y}`
        path += ` L ${nextX} ${stage.y}`
        // Vertical step to next level (if not last)
        if (i < stagePositions.length - 1) {
          path += ` L ${nextX} ${stagePositions[i + 1].y}`
        }
      })
      return path
    }

    return (
      <div className="schedule-variant stepline-variant">
        <div className="variant-header">
          <span className="variant-title">Temperature Steps</span>
        </div>

        {/* Step chart visualization */}
        <div className="stepline-chart">
          <svg viewBox="0 0 100 100" className="stepline-svg" preserveAspectRatio="none">
            {/* Background temperature zones */}
            {stagePositions.map((stage, i) => {
              const nextX = i < stagePositions.length - 1 ? stagePositions[i + 1].x : 100
              return (
                <rect
                  key={stage.id}
                  x={stage.x}
                  y={0}
                  width={nextX - stage.x}
                  height={100}
                  fill={stage.color}
                  opacity={0.15}
                />
              )
            })}

            {/* Grid lines */}
            <line x1="0" y1="50" x2="100" y2="50" stroke="#444" strokeWidth="0.3" strokeDasharray="2 2" />
            <line x1="0" y1="25" x2="100" y2="25" stroke="#333" strokeWidth="0.2" strokeDasharray="1 3" />
            <line x1="0" y1="75" x2="100" y2="75" stroke="#333" strokeWidth="0.2" strokeDasharray="1 3" />

            {/* Step line */}
            <path
              d={buildStepPath()}
              fill="none"
              stroke="#fff"
              strokeWidth="2.5"
              strokeLinecap="square"
            />

            {/* Colored overlay segments */}
            {stagePositions.map((stage, i) => {
              const nextX = i < stagePositions.length - 1 ? stagePositions[i + 1].x : 100
              return (
                <line
                  key={`line-${stage.id}`}
                  x1={stage.x}
                  y1={stage.y}
                  x2={nextX}
                  y2={stage.y}
                  stroke={stage.color}
                  strokeWidth="3"
                  strokeLinecap="square"
                />
              )
            })}

            {/* Step markers */}
            {stagePositions.map((stage) => (
              <g key={`marker-${stage.id}`}>
                <rect
                  x={stage.x - 2}
                  y={stage.y - 3}
                  width={4}
                  height={6}
                  rx={1}
                  fill={stage.color}
                  stroke="#0a0a0a"
                  strokeWidth="1"
                />
              </g>
            ))}
          </svg>

          {/* Time markers */}
          <div className="stepline-time-markers">
            <span>10PM</span>
            <span>12AM</span>
            <span>2AM</span>
            <span>4AM</span>
            <span>6AM</span>
          </div>
        </div>

        {/* Stage cards */}
        <div className="stepline-stages">
          {groupedStages.map((stage) => (
            <div key={stage.id} className="stepline-stage-card" style={{ borderLeftColor: stage.color }}>
              <div className="stage-card-header">
                <span className="stage-card-name">{stage.name}</span>
                <span className="stage-card-time">{stage.startTime}</span>
              </div>
              <div className="stage-card-controls">
                <button onClick={() => updateGroupedStageTemp(stage.id, -1)}><Minus size={14} /></button>
                <span className="stage-card-temp" style={{ color: stage.color }}>
                  {stage.temp > 0 ? '+' : ''}{stage.temp}
                </span>
                <button onClick={() => updateGroupedStageTemp(stage.id, 1)}><Plus size={14} /></button>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  // Render the selected variant
  const renderVariant = () => {
    switch (variant) {
      case 'blocks': return renderBlocksVariant()
      case 'list': return renderListVariant()
      case 'timeline': return renderTimelineVariant()
      case 'clock': return renderClockVariant()
      case 'gradient': return renderGradientVariant()
      case 'accordion': return renderAccordionVariant()
      case 'dualslider': return renderDualSliderVariant()
      case 'smartpresets': return renderSmartPresetsVariant()
      case 'grid': return renderGridVariant()
      case 'wedges': return renderWedgesVariant()
      case 'accordiongraph': return renderAccordionGraphVariant()
      case 'smoothline': return renderSmoothLineVariant()
      case 'stepline': return renderStepLineVariant()
    }
  }

  return (
    <div className="screen-content schedule-screen">
      {/* SIDE SELECTOR */}
      <div className="schedule-side-selector">
        <div className="schedule-side-buttons">
          <button
            className={`schedule-side-btn ${selectedSide === 'left' ? 'active' : ''} ${selectedSide === 'both' ? 'linked' : ''}`}
            onClick={() => handleSideSelect('left')}
          >
            <span className="side-label">Left Side</span>
          </button>
          <button
            className={`schedule-side-btn ${selectedSide === 'right' ? 'active' : ''} ${selectedSide === 'both' ? 'linked' : ''}`}
            onClick={() => handleSideSelect('right')}
          >
            <span className="side-label">Right Side</span>
          </button>
        </div>
        <button
          className={`schedule-link-btn ${selectedSide === 'both' ? 'linked' : ''}`}
          onClick={handleLinkToggle}
          title={selectedSide === 'both' ? 'Unlink sides' : 'Link both sides'}
        >
          {selectedSide === 'both' ? <Link size={16} /> : <Unlink size={16} />}
        </button>
      </div>

      {/* SELECTED VARIANT */}
      <div className="schedule-card variant-card">
        {renderVariant()}
      </div>

      {/* PRESET PROFILES (shared across variants) */}
      <div className="schedule-card profile-card">
        <div className="profile-section">
          <span className="profile-label">QUICK PRESETS</span>
          <div className="profile-buttons">
            <button
              className={`profile-btn ${sleepProfile === 'cool' ? 'active' : ''}`}
              onClick={() => setSleepProfile('cool')}
            >
              <span className="profile-name">Cool Sleeper</span>
              <span className="profile-desc">Extra cool all night</span>
            </button>
            <button
              className={`profile-btn ${sleepProfile === 'balanced' ? 'active' : ''}`}
              onClick={() => setSleepProfile('balanced')}
            >
              <span className="profile-name">Balanced</span>
              <span className="profile-desc">Science-backed</span>
            </button>
            <button
              className={`profile-btn ${sleepProfile === 'warm' ? 'active' : ''}`}
              onClick={() => setSleepProfile('warm')}
            >
              <span className="profile-name">Warm Sleeper</span>
              <span className="profile-desc">Warmer temps</span>
            </button>
          </div>
        </div>
      </div>

      {/* Sleep Time Card */}
      <div className="schedule-card sleep-time-card">
        <div className="sleep-row">
          <div className="time-block">
            <div className="time-icon moon">
              <Moon size={18} />
            </div>
            <div className="time-info">
              <span className="time-value">10:00 PM</span>
              <span className="time-label">BEDTIME</span>
            </div>
          </div>

          <div className="duration-badge">9h</div>

          <div className="time-block right">
            <div className="time-info">
              <span className="time-value">7:00 AM</span>
              <span className="time-label">WAKE UP</span>
            </div>
            <div className="time-icon sun">
              <Sun size={18} />
            </div>
          </div>
        </div>

        {/* Day Selector */}
        <div className="day-selector">
          {days.map((day, index) => (
            <button
              key={index}
              className={`day-btn ${selectedDays.includes(index) ? 'active' : ''}`}
              onClick={() => toggleDay(index)}
            >
              {day}
            </button>
          ))}
        </div>
      </div>

      {/* Schedule Active Toggle */}
      <div className="schedule-card toggle-card">
        <div className="toggle-row">
          <div className="toggle-info">
            <span className="toggle-title">Schedule Active</span>
            <span className="toggle-subtitle">{selectedDays.length} days selected</span>
          </div>
          <button
            className={`toggle-switch ${scheduleActive ? 'active' : ''}`}
            onClick={() => setScheduleActive(!scheduleActive)}
          >
            <span className="toggle-knob" />
          </button>
        </div>
      </div>
    </div>
  )
}

export default ScheduleScreen
