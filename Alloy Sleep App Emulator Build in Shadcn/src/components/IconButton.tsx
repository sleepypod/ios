import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import BatteryMidLevel from './icons/BatteryMidLevel.tsx'
import CurvedQuestionMarkOutline from './icons/CurvedQuestionMarkOutline.tsx'


// Component
function IconButton({
          buttonClass,
          iconType,
        }: {
          buttonClass: string;
          iconType: "BatteryMidLevel" | "CurvedQuestionMarkOutline";
        }) {
          return (
            <button type="button" className={buttonClass}>
              <div className="c8wKJ1_kQv9ug5C9d7_O">
                {iconType === "BatteryMidLevel" ? <BatteryMidLevel /> : <CurvedQuestionMarkOutline />}
              </div>
            </button>
          );
        }

export default IconButton
