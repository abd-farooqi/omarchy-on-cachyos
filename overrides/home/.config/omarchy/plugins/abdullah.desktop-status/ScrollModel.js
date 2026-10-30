function scrollPosition(current, contentHeight, viewportHeight, pixelDelta, angleDelta, wheelStep) {
  var delta = pixelDelta !== 0 ? pixelDelta * 2 : angleDelta / 120 * wheelStep
  return Math.max(0, Math.min(Math.max(0, contentHeight - viewportHeight), current - delta))
}
