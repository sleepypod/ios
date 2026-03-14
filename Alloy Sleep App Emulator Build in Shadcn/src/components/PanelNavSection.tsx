import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import CubeThreedOutline from './icons/CubeThreedOutline.tsx'
import CameraFrontViewOutline from './icons/CameraFrontViewOutline.tsx'
import PanelNavItem from './PanelNavItem.tsx'
import Section from './Section.tsx'


// Component
function PanelNavSection() {
            return (
                <section className="zksf_EGo5nDAVsdKZdr6">
                    <PanelNavItem
                        label="Prototypes"
                        icon={<CubeThreedOutline />}
                        isActive={false}
                    />
                    <PanelNavItem
                        label="Captures"
                        icon={<CameraFrontViewOutline />}
                        isActive={true}
                    />
                </section>
            );
        }

export default PanelNavSection
