import React from 'react'
import type { JSX } from 'react/jsx-runtime'



// Component
function PanelNavItem({
            label,
            icon,
            isActive
        }: {
            label: string;
            icon: React.ReactNode;
            isActive?: boolean;
        }) {
            return (
                <a
                    className={
                        "B4nTTpvfwWAijLmlZDD0"
                        + (isActive ? " TnYtseMio36G9LWurit0 active" : "")
                    }
                >
                    <div className={"aFWbbnm3vOT_YsHId9JG"}>
                        {icon}
                    </div>
                    <span className={"aNKdN5YIghXemrJwFXgS"}>
                        {label}
                    </span>
                </a>
            );
        }

export default PanelNavItem
