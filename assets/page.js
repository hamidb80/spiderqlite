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

function inspect(a) {
  console.log(a)
  return a
}

function kvmap(obj, fn) {
  var result = []
  for (let k in obj) {
    result.push(fn(k, obj[k]))
  }
  return result
}

// bg, fg, st
const colors = [
  ['#ffffff', '#889bad', '#a5b7cf'], // white
  ['#ecedef', '#778696', '#9eaabb'], // smoke
  ['#dfe2e4', '#617288', '#808fa6'], // road
  ['#fef5a6', '#958505', '#dec908'], // yellow
  ['#ffdda9', '#a7690e', '#e99619'], // orange
  ['#ffcfc9', '#b26156', '#ff634e'], // red
  ['#fbc4e2', '#af467e', '#e43e97'], // peach
  ['#f3d2ff', '#7a5a86', '#c86fe9'], // pink
  ['#dac4fd', '#7453ab', '#a46bff'], // purple
  ['#d0d5fe', '#4e57a3', '#7886f4'], // purpleLow
  ['#b6e5ff', '#2d7aa5', '#399bd3'], // blue
  ['#adefe3', '#027b64', '#00d2ad'], // diomand
  ['#c4fad6', '#298849', '#25ba58'], // mint
  ['#cbfbad', '#479417', '#52d500'], // green
  ['#e6f8a0', '#617900', '#a5cc08'], // lemon
]

function pick(array) {
  return array[Math.floor(Math.random() * array.length)]
}
function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

// --------- setup -----------------------------------

up.macro('[smooth-link]', link => {
  link.setAttribute('up-transition', 'cross-fade')
  link.setAttribute('up-duration', '200')
})


up.compiler('code', element => {
  element.innerHTML = dedent(element.innerHTML)
  hljs.highlightElement(element)
})

up.compiler('textarea[lang]', element => {
  element.value = dedent(element.value)
})

up.compiler("[redirect]", link => {
  up.follow(link)
})

function mkMap(a, b) {
  let result = {}
  for (let i = 0; i < a.length; i++) {
    result[a[i]] = b[i % b.length]
  }
  console.log(result)
  return result
}

up.compiler("[vis-graph]", (container, data) => {
  console.log(data)

  let nodeColors = shuffle(colors.map(it => it[0]))
  let edgeColors = shuffle(colors.map(it => it[2]))

  let tagColorNodeMap = mkMap(data['node_tags'], nodeColors)
  let tagColorEdgeMap = mkMap(data['edge_tags'], edgeColors)

  let newnodes = kvmap(data['nodes'], (_, it) => ({
    id: it['__id'],
    label: `#${it['__tag']} ${it['__id']}`,
    color: tagColorNodeMap[it['__tag']]
  }))
  let newedges = kvmap(data['edges'], (_, it) => ({
    id: it['__id'],
    from: it['__head'],
    to: it['__tail'],
    color: tagColorEdgeMap[it['__tag']],
    label: it['__tag']
  }))

  let nodes = new vis.DataSet(newnodes)
  let edges = new vis.DataSet(newedges)

  container.style.height = 200
  let network = new vis.Network(container, { nodes, edges }, {
    // nodes: {
    //   font: {
    //     size: 22
    //   },
    // },
    edges: {
      font: {
        align: "top"
      },
      arrows: {
        to: { enabled: true, scaleFactor: 1, type: "arrow" }
      }
    }
  })

  network.on("click", function (params) {
    let node_id = this.getNodeAt(params.pointer.DOM)
    let edge_id = this.getEdgeAt(params.pointer.DOM)

    console.log(node_id, edge_id)

    if (node_id) {
      document.querySelector('[name=node-id]').value = node_id
      up.submit('#node-get')
    }
    else if (edge_id) {
      document.querySelector('[name=edge-id]').value = edge_id
      up.submit('#edge-get')
    }

  })
})
