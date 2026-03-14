import React from 'react'
import type { JSX } from 'react/jsx-runtime'



// Component
function ChatFrame({
    id,
    tabIndex,
    title,
    sandbox
}: {
    id: string;
    tabIndex: string;
    title: string;
    sandbox: string;
}) {
    return (
        <iframe
            id={id}
            style={{
                position: "absolute",
                opacity: "0",
                width: "1px",
                height: "1px",
                top: "0",
                left: "0",
                border: "none",
                display: "block",
                zIndex: "-1",
                pointerEvents: "none"
            }}
            tabIndex={tabIndex}
            title={title}
            sandbox={sandbox}
            src="frames/c846afba-58f1-4cc8-8713-8bbc67af222e/index.html"
        >
        </iframe>
    );
}

export default ChatFrame
