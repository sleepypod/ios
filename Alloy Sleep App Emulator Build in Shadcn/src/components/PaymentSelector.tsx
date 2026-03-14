import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import CreditCardOutline from './icons/CreditCardOutline.tsx'
import ChevronDown from './icons/ChevronDown.tsx'


// Component
function PaymentSelector({
          label,
        }: {
          label: string;
        }) {
          return (
            <button type="button" className="LKoZucTpa4wJDkaowvQ1 ZTUQ3H7RbP5UecXW1MYH">
              <div className="lFgseKnmgbVS5aBOBFsx">
                <div className="ryebsr70rPsuTrtm5xBJ iDHv6q5EOc3C0IYV_FP9 nsA8AOhTB0uUDMTYee4H">
                  <div className="XyLKqSMPBTGaL5I4fbEE">
                    <CreditCardOutline />
                  </div>
                </div>
                <span style={{ textTransform: "capitalize" }}>
                  {label}
                </span>
              </div>
              <ChevronDown />
            </button>
          );
        }

export default PaymentSelector
