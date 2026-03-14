import { Clock, Info, Home, MapPin, Minus, Plus, TrendingUp, TrendingDown, Link, Unlink, Power } from 'lucide-react'

interface TempScreenProps {
  leftTemp: number
  rightTemp: number
  leftOff?: boolean
  rightOff?: boolean
  selectedSides: Set<'left' | 'right'>
  leftOccupied?: boolean
  rightOccupied?: boolean
  onTempChange: (delta: number) => void
  onSideToggle: (side: 'left' | 'right') => void
  onLinkToggle?: () => void
  onOffToggle?: () => void
}

function TempScreen({ leftTemp, rightTemp, leftOff = false, rightOff = false, selectedSides, leftOccupied = true, rightOccupied = false, onTempChange, onSideToggle, onLinkToggle, onOffToggle }: TempScreenProps) {
  const leftSideFahrenheit = 80 + leftTemp * 2
  const rightSideFahrenheit = 80 + rightTemp * 2

  const isBothSelected = selectedSides.has('left') && selectedSides.has('right')

  // Check if selected side(s) are off
  const isSelectedOff = isBothSelected
    ? (leftOff && rightOff)
    : selectedSides.has('left')
    ? leftOff
    : rightOff

  // Display temperature based on selection
  const displayTemp = isBothSelected
    ? leftTemp
    : selectedSides.has('left')
    ? leftTemp
    : rightTemp

  const displayFahrenheit = isBothSelected
    ? leftSideFahrenheit
    : selectedSides.has('left')
    ? leftSideFahrenheit
    : rightSideFahrenheit

  const currentTemp = 82
  const isWarming = displayTemp > 0

  const getGlowColor = () => {
    if (isSelectedOff) {
      return `rgba(60, 60, 60, 0.3)`
    }
    if (displayTemp > 0) {
      return `rgba(220, 100, 70, 0.6)`
    } else if (displayTemp < 0) {
      return `rgba(70, 130, 200, 0.6)`
    }
    return `rgba(100, 100, 100, 0.3)`
  }

  const handleLinkClick = () => {
    if (onLinkToggle) {
      onLinkToggle()
    }
  }

  return (
    <div className="screen-content">
      {/* Priming Alert */}
      <div className="alert-banner priming-alert">
        <Info size={18} />
        <span>Device is currently priming</span>
      </div>

      {/* Alarm Banner */}
      <div className="alert-banner alarm-banner">
        <div className="alarm-left">
          <Clock size={18} />
          <span>Alarm</span>
        </div>
        <div className="alarm-right">
          <button className="time-badge">8:00 AM</button>
          <button className="disable-btn">DISABLE</button>
        </div>
      </div>

      {/* Temperature Dial */}
      <div className="dial-container">
        <div
          className="temperature-dial"
          style={{
            boxShadow: `0 0 80px 20px ${getGlowColor()}, inset 0 0 60px rgba(0,0,0,0.8)`
          }}
        >
          <div className="dial-ring" style={{ borderColor: isSelectedOff ? '#333' : displayTemp > 0 ? '#dc6646' : displayTemp < 0 ? '#4682c8' : '#444' }} />
          <div className="dial-content">
            {isSelectedOff ? (
              <>
                <span className="dial-label">
                  {isBothSelected ? 'BOTH SIDES' : selectedSides.has('left') ? 'LEFT SIDE' : 'RIGHT SIDE'}
                </span>
                <span className="dial-value off">OFF</span>
                <div className="dial-temp">
                  <span className="temp-value off-hint">Tap to turn on</span>
                </div>
              </>
            ) : (
              <>
                <span className="dial-label">
                  {isBothSelected ? 'BOTH SIDES' : isWarming ? 'WARMING TO' : displayTemp < 0 ? 'COOLING TO' : 'SET TO'}
                </span>
                <span className={`dial-value ${isWarming ? 'warm' : displayTemp < 0 ? 'cool' : ''}`}>
                  {displayTemp > 0 ? '+' : ''}{displayTemp}
                </span>
                <div className="dial-temp">
                  <span className="temp-value">{displayFahrenheit}°</span>
                  <span className="temp-unit">F</span>
                </div>
                <div className="dial-now">
                  <span className="now-label">NOW</span>
                  <span className="now-value">0 · {currentTemp}°F</span>
                </div>
              </>
            )}
          </div>
        </div>

        {/* Temperature Controls */}
        <div className="temp-controls">
          <button
            className="temp-btn"
            onClick={() => onTempChange(-1)}
            disabled={isSelectedOff}
          >
            <Minus size={24} />
          </button>
          <button
            className={`temp-btn off-btn ${isSelectedOff ? 'is-off' : ''}`}
            onClick={() => onOffToggle?.()}
            title={isSelectedOff ? 'Turn on' : 'Turn off'}
          >
            <Power size={20} />
            <span className="off-label">{isSelectedOff ? 'ON' : 'OFF'}</span>
          </button>
          <button
            className="temp-btn"
            onClick={() => onTempChange(1)}
            disabled={isSelectedOff}
          >
            <Plus size={24} />
          </button>
        </div>
      </div>

      {/* Environment Info */}
      <div className="environment-info">
        <div className="env-item">
          <Home size={16} />
          <span className="env-value">72°F</span>
          <span className="env-label">Inside</span>
        </div>
        <div className="env-item">
          <MapPin size={16} />
          <span className="env-value">45°F</span>
          <span className="env-label">SF</span>
        </div>
      </div>

      {/* Side Selector with Floating Link Button */}
      <div className="side-selector-container">
        <div className="side-selector-wrapper">
          <div className="side-selector">
            <button
              className={`side-btn ${selectedSides.has('left') && !isBothSelected ? 'active' : ''} ${isBothSelected ? 'linked' : ''} ${leftOff ? 'is-off' : ''}`}
              onClick={() => !isBothSelected && onSideToggle('left')}
            >
              <span className="side-name-row">
                <span className="side-name">Left Side</span>
                {leftOccupied && !leftOff && <span className="presence-dot" title="In bed" />}
              </span>
              <div className="side-info">
                {leftOff ? (
                  <span className="side-off-label">OFF</span>
                ) : (
                  <>
                    {leftTemp > 0 ? (
                      <TrendingUp size={14} className="trend-icon warm" />
                    ) : leftTemp < 0 ? (
                      <TrendingDown size={14} className="trend-icon cool" />
                    ) : null}
                    <span>{leftTemp > 0 ? '+' : ''}{leftTemp} · {leftSideFahrenheit}°F</span>
                  </>
                )}
              </div>
            </button>

            <button
              className={`side-btn ${selectedSides.has('right') && !isBothSelected ? 'active' : ''} ${isBothSelected ? 'linked' : ''} ${rightOff ? 'is-off' : ''}`}
              onClick={() => !isBothSelected && onSideToggle('right')}
            >
              <span className="side-name-row">
                <span className="side-name">Right Side</span>
                {rightOccupied && !rightOff && <span className="presence-dot" title="In bed" />}
              </span>
              <div className="side-info">
                {rightOff ? (
                  <span className="side-off-label">OFF</span>
                ) : (
                  <>
                    {rightTemp > 0 ? (
                      <TrendingUp size={14} className="trend-icon warm" />
                    ) : rightTemp < 0 ? (
                      <TrendingDown size={14} className="trend-icon cool" />
                    ) : null}
                    <span>{rightTemp > 0 ? '+' : ''}{rightTemp} · {rightSideFahrenheit}°F</span>
                  </>
                )}
              </div>
            </button>
          </div>

          {/* Floating Link/Unlink Button */}
          <button
            className={`link-btn-floating ${isBothSelected ? 'linked' : ''}`}
            onClick={handleLinkClick}
            title={isBothSelected ? 'Unlink sides' : 'Link both sides'}
          >
            {isBothSelected ? <Link size={16} /> : <Unlink size={16} />}
          </button>
        </div>

        {/* Selection hint */}
        {isBothSelected && (
          <div className="selection-hint">
            Adjusting temperature for both sides
          </div>
        )}
      </div>
    </div>
  )
}

export default TempScreen
