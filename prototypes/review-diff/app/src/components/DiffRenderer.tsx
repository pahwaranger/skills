import { html } from 'diff2html'
import { ColorSchemeType } from 'diff2html/lib/types'

interface DiffRendererProps {
  rawDiff: string
  view: 'split' | 'unified'
}

// Thin wrapper around diff2html — used by all three variants.
// The .diff-renderer CSS class hides diff2html's own file header
// (each variant renders its own) and resets the wrapper background.
export default function DiffRenderer({ rawDiff, view }: DiffRendererProps) {
  const __html = html(rawDiff, {
    drawFileList: false,
    outputFormat: view === 'split' ? 'side-by-side' : 'line-by-line',
    colorScheme: ColorSchemeType.AUTO,
    matching: 'lines',
  })
  return <div className="diff-renderer" dangerouslySetInnerHTML={{ __html }} />
}
