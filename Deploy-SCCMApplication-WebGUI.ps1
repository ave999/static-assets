import React, { useEffect, useRef, useState } from 'react'
import type { SessionEngine } from '../engine/SessionEngine'
import type { ChunkPartialEvent, SegmentFinalEvent } from '../engine/types'

type UiSegment = {
  id: string
  text: string
  timestamp: Date
  isFinal: boolean
}

interface TranscriptDisplayProps {
  engine: SessionEngine | null
  isActive: boolean
  // Optional upgrade later:
  // sessionStartWallMs?: number
}

export const TranscriptDisplay: React.FC<TranscriptDisplayProps> = ({ engine, isActive }) => {
  const [segments, setSegments] = useState<UiSegment[]>([])
  const containerRef = useRef<HTMLDivElement>(null)
  const shouldAutoScroll = useRef(true)

  // Reset when a new transcription run starts
  useEffect(() => {
    if (isActive) {
      setSegments([])
    }
  }, [isActive])

  useEffect(() => {
    if (shouldAutoScroll.current && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight
    }
  }, [segments])

  const handleScroll = () => {
    if (!containerRef.current) return

    const { scrollTop, scrollHeight, clientHeight } = containerRef.current
    const isAtBottom = Math.abs(scrollHeight - scrollTop - clientHeight) < 10
    shouldAutoScroll.current = isAtBottom
  }

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  useEffect(() => {
    if (!engine) return

    // OPTION A: show low-latency chunk stream, with “Processing…” styling.
    const offChunk = engine.on('chunk.partial', (evt: ChunkPartialEvent) => {
      const newSeg: UiSegment = {
        id: evt.chunk_id,
        text: evt.text,
        timestamp: new Date(), // or map from sessionStartWallMs + evt.t_end_ms
        isFinal: false,
      }

      setSegments((prev) => {
        // Replace last “processing” line to mimic your prior UX
        if (prev.length > 0 && !prev[prev.length - 1].isFinal) {
          return [...prev.slice(0, -1), newSeg]
        }
        return [...prev, newSeg]
      })
    })

    // OPTIONAL: finalize on segment boundaries so you “lock in” text
    // If you enable this, you’ll see stable blocks (final) rather than only rolling partials.
    const offSeg = engine.on('segment.final', (evt: SegmentFinalEvent) => {
      const finalSeg: UiSegment = {
        id: evt.segment_id,
        text: evt.text,
        timestamp: new Date(), // or map from sessionStartWallMs + evt.t_end_ms
        isFinal: true,
      }

      setSegments((prev) => {
        // If last item is non-final (processing), replace it with the final segment
        if (prev.length > 0 && !prev[prev.length - 1].isFinal) {
          return [...prev.slice(0, -1), finalSeg]
        }
        return [...prev, finalSeg]
      })
    })

    return () => {
      offChunk()
      offSeg()
    }
  }, [engine])

  return (
    <div className="flex flex-col h-full">
      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto rounded-xl p-6 space-y-3 custom-scrollbar transition-all duration-300"
        style={{
          backgroundColor: 'var(--bg-tertiary)',
          borderColor: 'var(--border-color)',
          borderWidth: '1px',
        }}
      >
        {segments.length === 0 ? (
          <div className="text-center py-16">
            <div className="inline-block">
              <div className="flex items-center gap-3 mb-3">
                <div
                  className="h-8 w-8 border-4 rounded-full animate-spin"
                  style={{
                    borderColor: 'var(--accent-primary)',
                    borderTopColor: 'transparent',
                    opacity: 0.3,
                  }}
                ></div>
                <p className="font-medium" style={{ color: 'var(--text-secondary)' }}>
                  {isActive ? 'Analyzing audio stream...' : 'Ready to transcribe'}
                </p>
              </div>
              <p className="text-sm" style={{ color: 'var(--text-tertiary)', opacity: 0.6 }}>
                {isActive ? 'Waiting for speech input' : 'Click "Start Transcription" to begin'}
              </p>
            </div>
          </div>
        ) : (
          segments.map((segment, index) => (
            <div
              key={segment.id}
              className="group flex gap-3 p-3 rounded-lg transition-all duration-300 hover:scale-[1.01]"
              style={{
                backgroundColor: segment.isFinal ? 'var(--bg-secondary)' : 'rgba(234, 179, 8, 0.05)',
                borderColor: segment.isFinal ? 'var(--border-color)' : 'rgba(234, 179, 8, 0.2)',
                borderWidth: '1px',
                animation: !segment.isFinal ? 'pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite' : 'none',
                animationDelay: `${index * 0.1}s`,
              }}
            >
              <span
                className="text-xs font-mono mt-1 shrink-0 px-2 py-1 rounded"
                style={{
                  color: 'var(--text-tertiary)',
                  backgroundColor: 'var(--bg-tertiary)',
                }}
              >
                {formatTime(segment.timestamp)}
              </span>
              <p
                className="flex-1 leading-relaxed"
                style={{
                  color: segment.isFinal ? 'var(--text-primary)' : '#eab308',
                  fontStyle: segment.isFinal ? 'normal' : 'italic',
                  fontWeight: segment.isFinal ? 400 : 300,
                }}
              >
                {segment.text}
              </p>
              {!segment.isFinal && (
                <span className="text-xs mt-1" style={{ color: '#facc15' }}>
                  Processing...
                </span>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  )
}
