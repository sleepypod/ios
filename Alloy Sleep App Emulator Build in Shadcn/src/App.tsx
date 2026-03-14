import React, { useState, useRef, useEffect } from 'react'
import './freesleep.css'
import { Thermometer, Calendar, BarChart3, Activity, Settings, Wifi, Power, ChevronDown } from 'lucide-react'
import TempScreen from './components/TempScreen'
import ScheduleScreen from './components/ScheduleScreen'
import DataScreen from './components/DataScreen'
import StatusScreen from './components/StatusScreen'
import SettingsScreen from './components/SettingsScreen'

type ScheduleVariant = 'blocks' | 'list' | 'timeline' | 'clock' | 'gradient' | 'accordion' | 'dualslider' | 'smartpresets' | 'grid' | 'wedges' | 'accordiongraph' | 'smoothline' | 'stepline'

function App() {
  const [leftTemp, setLeftTemp] = useState(2)
  const [rightTemp, setRightTemp] = useState(-1)
  const [leftOff, setLeftOff] = useState(false)
  const [rightOff, setRightOff] = useState(false)
  const [selectedSides, setSelectedSides] = useState<Set<'left' | 'right'>>(new Set(['left']))
  const [activeTab, setActiveTab] = useState('temp')
  const [scheduleVariant, setScheduleVariant] = useState<ScheduleVariant>('blocks')
  const [variantDropdownOpen, setVariantDropdownOpen] = useState(false)
  const dropdownRef = useRef<HTMLDivElement>(null)

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setVariantDropdownOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const variantLabels: Record<ScheduleVariant, string> = {
    blocks: 'Blocks',
    list: 'List',
    timeline: 'Timeline',
    clock: 'Clock',
    gradient: 'Gradient',
    accordion: 'Accordion',
    dualslider: 'Dual Slider',
    smartpresets: 'Smart Presets',
    grid: 'Grid',
    wedges: 'Wedges',
    accordiongraph: 'Accordion Graph',
    smoothline: 'Smooth Line',
    stepline: 'Step Line'
  }

  const handleTempChange = (delta: number) => {
    if (selectedSides.has('left')) {
      setLeftTemp(prev => Math.max(-10, Math.min(10, prev + delta)))
    }
    if (selectedSides.has('right')) {
      setRightTemp(prev => Math.max(-10, Math.min(10, prev + delta)))
    }
  }

  const handleSideToggle = (side: 'left' | 'right') => {
    // Simple toggle between left and right (not both)
    setSelectedSides(new Set([side]))
  }

  const handleLinkToggle = () => {
    setSelectedSides(prev => {
      // If both are selected, unlink and select left
      if (prev.size === 2) {
        return new Set(['left'])
      }
      // If only one is selected, link both
      return new Set(['left', 'right'])
    })
  }

  const handleOffToggle = () => {
    // Toggle off state for selected sides
    if (selectedSides.has('left')) {
      setLeftOff(prev => !prev)
    }
    if (selectedSides.has('right')) {
      setRightOff(prev => !prev)
    }
  }

  const renderScreen = () => {
    switch (activeTab) {
      case 'temp':
        return (
          <TempScreen
            leftTemp={leftTemp}
            rightTemp={rightTemp}
            leftOff={leftOff}
            rightOff={rightOff}
            selectedSides={selectedSides}
            onTempChange={handleTempChange}
            onSideToggle={handleSideToggle}
            onLinkToggle={handleLinkToggle}
            onOffToggle={handleOffToggle}
          />
        )
      case 'schedule':
        return <ScheduleScreen variant={scheduleVariant} />
      case 'data':
        return <DataScreen />
      case 'status':
        return <StatusScreen />
      case 'settings':
        return <SettingsScreen />
      default:
        return null
    }
  }

  return (
    <body className="freesleep-body">
      <div className="freesleep-app">
        {/* Header */}
        <header className="freesleep-header">
          <div className="wifi-status">
            <Wifi size={18} />
            <span>82%</span>
          </div>

          {/* Variant Dropdown - only show on Schedule tab */}
          {activeTab === 'schedule' && (
            <div className="variant-dropdown" ref={dropdownRef}>
              <button
                className="variant-dropdown-trigger"
                onClick={() => setVariantDropdownOpen(!variantDropdownOpen)}
              >
                <span className="variant-dropdown-label">UI:</span>
                <span className="variant-dropdown-value">{variantLabels[scheduleVariant]}</span>
                <ChevronDown size={14} className={`variant-chevron ${variantDropdownOpen ? 'open' : ''}`} />
              </button>
              {variantDropdownOpen && (
                <div className="variant-dropdown-menu">
                  {(Object.keys(variantLabels) as ScheduleVariant[]).map((key) => (
                    <button
                      key={key}
                      className={`variant-dropdown-item ${scheduleVariant === key ? 'active' : ''}`}
                      onClick={() => {
                        setScheduleVariant(key)
                        setVariantDropdownOpen(false)
                      }}
                    >
                      {variantLabels[key]}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          <button className="power-button">
            <Power size={20} />
          </button>
        </header>

        {/* Screen Content */}
        {renderScreen()}

        {/* Bottom Navigation */}
        <nav className="bottom-nav">
          <button
            className={`nav-item ${activeTab === 'temp' ? 'active' : ''}`}
            onClick={() => setActiveTab('temp')}
          >
            <Thermometer size={22} />
            <span>Temp</span>
          </button>
          <button
            className={`nav-item ${activeTab === 'schedule' ? 'active' : ''}`}
            onClick={() => setActiveTab('schedule')}
          >
            <Calendar size={22} />
            <span>Schedule</span>
          </button>
          <button
            className={`nav-item ${activeTab === 'data' ? 'active' : ''}`}
            onClick={() => setActiveTab('data')}
          >
            <BarChart3 size={22} />
            <span>Data</span>
          </button>
          <button
            className={`nav-item ${activeTab === 'status' ? 'active' : ''}`}
            onClick={() => setActiveTab('status')}
          >
            <Activity size={22} />
            <span>Status</span>
          </button>
          <button
            className={`nav-item ${activeTab === 'settings' ? 'active' : ''}`}
            onClick={() => setActiveTab('settings')}
          >
            <Settings size={22} />
            <span>Settings</span>
          </button>
        </nav>
      </div>
    </body>
  )
}

export default App
