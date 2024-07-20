
function dedent(input) {
  // Split the input into lines
  const lines = input.split('\n')

  // Find the minimum indentation among all lines
  let minIndent = Infinity
  lines.forEach(line => {
    if (line.trim().length != 0) {
      const match = line.match(/^\s*/)
      if (match && match[0].length < minIndent) {
        minIndent = match[0].length
      }
    }
  })

  // Remove the minimum indentation from each line
  const dedentedLines = lines.map(line => line.substring(minIndent))
  // Join the lines back together and return
  const result = dedentedLines.join('\n')

  return result.trim()
}

function replInner(el, replacer) {
  el.innerHTML = replacer(el.innerHTML)
}

for (let codeEl of document.querySelectorAll('code')) {
  replInner(codeEl, dedent)
  hljs.highlightElement(codeEl)
}