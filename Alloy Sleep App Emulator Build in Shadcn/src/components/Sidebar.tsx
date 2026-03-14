import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import BatteryMidLevel from './icons/BatteryMidLevel.tsx'
import PaymentSelector from './PaymentSelector.tsx'
import IconButton from './IconButton.tsx'
import BlankButton from './BlankButton.tsx'
import Section from './Section.tsx'
import SearchBar from './SearchBar.tsx'
import PanelNavSection from './PanelNavSection.tsx'


// Component
function Sidebar() {
            return (
                <nav className="_E1_tmrKNy8UNLOHrMSk" style={{ width: "270px" }}>
                    <div className="PeBlEAW_yMMvMyfKsqMy">
                        <div className="czq5yJl72BYAOFMLgnNJ">
                            <div className="vVSzFfHNYbpeG94mJqc0">
                                <div className="RHUGNGT32BRZxpL_rywp">
                                    <div className="ZgS0zvTjWV7i1q5UOGS0">
                                        <PaymentSelector label="jonathanng" />
                                    </div>
                                    <div className="qgkZOrVoeOPHBXZ60XAM">
                                        <IconButton
                                            buttonClass="LKoZucTpa4wJDkaowvQ1 mSllZOeqIfgCCQ6cfMk6"
                                            iconType="BatteryMidLevel"
                                        />
                                    </div>
                                </div>
                                <div className="fdvCINcWke_1odWGEhGg">
                                    <SearchBar placeholder="Search" />
                                    <BlankButton />
                                </div>
                            </div>
                            <div className="FudfhfozYFH2JCEt3j95">
                                <PanelNavSection />
                            </div>
                            <Section />
                        </div>
                    </div>
                </nav>
            );
        }

export default Sidebar
