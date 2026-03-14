import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import Section from './Section.tsx'


// Component
function FocusableSection() {
            return (
                <section tabIndex={-1}>

                </section>
            );
        }

export default FocusableSection
