.pragma library

// An app's icon as a view in Basecamp can show it. The backend sends a data:
// URL, which Basecamp's sandbox blocks; `images` (Basecamp's SandboxImages,
// null outside Basecamp) turns it into an image only this view's engine reads.
function shown(images, url) {
    if (!url) return ""
    return images ? images.sourceFor(url) : url
}
