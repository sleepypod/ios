import React, { useState } from 'react'
import { Server, Cpu, Clock, Heart, Activity, RefreshCw, ChevronDown, ChevronRight, Check } from 'lucide-react'

interface ServiceItem {
  name: string
  description: string
  status: 'running' | 'stopped' | 'warning'
}

interface ServiceCategory {
  id: string
  name: string
  description: string
  icon: React.ReactNode
  iconBg: string
  services: ServiceItem[]
}

function StatusScreen() {
  const [expandedCategories, setExpandedCategories] = useState<string[]>(['core'])

  const totalServices = 18
  const healthyServices = 17

  const serviceCategories: ServiceCategory[] = [
    {
      id: 'core',
      name: 'Core Services',
      description: 'Essential system components',
      icon: <Server size={20} />,
      iconBg: '#4a90d9',
      services: [
        { name: 'Express Server', description: 'Running in demo mode', status: 'running' },
        { name: 'Database', description: 'SQLite connection', status: 'running' },
        { name: 'Job Scheduler', description: 'All jobs executed successfully', status: 'running' },
        { name: 'Logger', description: 'Application logs', status: 'running' },
      ]
    },
    {
      id: 'hardware',
      name: 'Hardware Interface',
      description: 'Device communication',
      icon: <Cpu size={20} />,
      iconBg: '#a080d0',
      services: [
        { name: 'Franken Sock', description: 'Socket interface', status: 'running' },
        { name: 'Franken Monitor', description: 'Gesture monitoring', status: 'warning' },
      ]
    },
    {
      id: 'schedules',
      name: 'Schedules',
      description: 'Automated routines',
      icon: <Clock size={20} />,
      iconBg: '#d4a84a',
      services: [
        { name: 'Sleep Schedule', description: 'Active', status: 'running' },
        { name: 'Wake Alarm', description: 'Set for 7:00 AM', status: 'running' },
        { name: 'Temperature Curve', description: 'Cool Sleeper profile', status: 'running' },
        { name: 'Auto Prime', description: 'Daily at 8 PM', status: 'running' },
        { name: 'Weekend Mode', description: 'Adjusted schedule', status: 'running' },
      ]
    },
    {
      id: 'biometrics',
      name: 'Biometrics & Analytics',
      description: 'Sleep tracking data',
      icon: <Heart size={20} />,
      iconBg: '#e05050',
      services: [
        { name: 'Heart Rate Monitor', description: 'Tracking active', status: 'running' },
        { name: 'HRV Analysis', description: 'Processing', status: 'running' },
        { name: 'Sleep Stage Detection', description: 'ML model v2.1', status: 'running' },
        { name: 'Movement Tracking', description: 'Piezo sensors', status: 'running' },
      ]
    },
    {
      id: 'calibration',
      name: 'Calibration',
      description: 'Sensor calibration',
      icon: <Activity size={20} />,
      iconBg: '#4ecdc4',
      services: [
        { name: 'Temperature Sensors', description: 'Last calibrated 2 days ago', status: 'running' },
        { name: 'Presence Detection', description: 'Calibrated', status: 'running' },
      ]
    },
    {
      id: 'system',
      name: 'System',
      description: 'System health',
      icon: <RefreshCw size={20} />,
      iconBg: '#888',
      services: [
        { name: 'System Monitor', description: 'All systems nominal', status: 'running' },
      ]
    },
  ]

  const toggleCategory = (categoryId: string) => {
    if (expandedCategories.includes(categoryId)) {
      setExpandedCategories(expandedCategories.filter(id => id !== categoryId))
    } else {
      setExpandedCategories([...expandedCategories, categoryId])
    }
  }

  const getRunningCount = (services: ServiceItem[]) => {
    return services.filter(s => s.status === 'running').length
  }

  const healthPercentage = (healthyServices / totalServices) * 100

  return (
    <div className="screen-content status-screen">
      {/* Health Status Circle */}
      <div className="status-card health-circle-card">
        <div className="health-circle">
          <svg viewBox="0 0 120 120" className="health-svg">
            {/* Background circle */}
            <circle
              cx="60"
              cy="60"
              r="54"
              fill="none"
              stroke="#222"
              strokeWidth="8"
            />
            {/* Progress circle */}
            <circle
              cx="60"
              cy="60"
              r="54"
              fill="none"
              stroke="#50c878"
              strokeWidth="8"
              strokeLinecap="round"
              strokeDasharray={`${healthPercentage * 3.39} 339`}
              transform="rotate(-90 60 60)"
            />
          </svg>
          <div className="health-content">
            <span className="health-number">{healthyServices}</span>
            <span className="health-label">OF {totalServices} HEALTHY</span>
          </div>
        </div>
        <div className="health-legend">
          <span className="legend-item">
            <span className="status-dot running" />
            {healthyServices} Running
          </span>
          <span className="legend-item">
            <span className="status-dot stopped" />
            {totalServices - healthyServices} Stopped
          </span>
        </div>
      </div>

      {/* Service Categories */}
      {serviceCategories.map((category) => {
        const isExpanded = expandedCategories.includes(category.id)
        const runningCount = getRunningCount(category.services)
        const totalCount = category.services.length

        return (
          <div key={category.id} className="status-card service-category">
            <button
              className="category-header"
              onClick={() => toggleCategory(category.id)}
            >
              <div className="category-icon" style={{ background: category.iconBg }}>
                {category.icon}
              </div>
              <div className="category-info">
                <span className="category-name">{category.name}</span>
                <span className="category-desc">{category.description}</span>
              </div>
              <div className="category-status">
                <span className={`status-badge ${runningCount === totalCount ? 'success' : 'warning'}`}>
                  <Check size={12} />
                  {runningCount}/{totalCount}
                </span>
                {isExpanded ? <ChevronDown size={20} /> : <ChevronRight size={20} />}
              </div>
            </button>

            {isExpanded && (
              <div className="category-services">
                {category.services.map((service, idx) => (
                  <div key={idx} className="service-item">
                    <div className="service-info">
                      <span className="service-name">{service.name}</span>
                      <span className="service-desc">{service.description}</span>
                    </div>
                    <span className={`status-dot ${service.status}`} />
                  </div>
                ))}
              </div>
            )}
          </div>
        )
      })}

      {/* Last Updated */}
      <div className="last-updated">
        Last updated: Just now
      </div>
    </div>
  )
}

export default StatusScreen
