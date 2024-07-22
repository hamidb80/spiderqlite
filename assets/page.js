
// --------- utils -----------------------------------

function dedent(text) {
  // removes common indentation from `text`
  const lines = text.split('\n')

  let minIndent = Infinity
  lines.forEach(line => {
    if (line.trim().length != 0) {
      const match = line.match(/^\s*/)
      if (match && match[0].length < minIndent) {
        minIndent = match[0].length
      }
    }
  })

  // Find the minimum indentation among all lines

  return lines
    .map(line => line.substring(minIndent)) // crop after minIndent
    .join('\n')
    .trim()
}

// --------- utils -----------------------------------

up.compiler('code', function (element) {
  element.innerHTML = dedent(element.innerHTML)
  hljs.highlightElement(element)
})
