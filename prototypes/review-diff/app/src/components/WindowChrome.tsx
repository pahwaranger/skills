// macOS-style window chrome: traffic lights + title + tab bar (Review active)
export default function WindowChrome() {
  return (
    <>
      <div className="titlebar">
        <div className="traffic">
          <span className="r" />
          <span className="y" />
          <span className="g" />
        </div>
        <span className="win-title">Steve</span>
      </div>
      <div className="tabs">
        <button className="tab active">
          <span className="glyph">↕</span>
          Review
        </button>
        <button className="tab">
          <span className="glyph">⚙</span>
          Settings
        </button>
      </div>
    </>
  )
}
