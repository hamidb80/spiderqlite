import std/[strformat, json, options]

import ../query_language/core
import ./config

import ./routes

# ------------------------------ combinators

proc redirectingHtml*(link: string): string =
  fmt"""
    <a href="{link}" smooth-link redirect >
      redirecting ...
    </a>
  """

template iff(cond, whentrue, whenfalse): untyped =
  if cond: whentrue
  else   : whenfalse

func navPartial(): string =
  fmt"""
  <nav class="navbar navbar-expand-lg bg-primary px-3 py-1" data-bs-theme="dark">
    <a class="text-white mb-1 text-decoration-none" href="/" smooth-link>
      <img src="/static/spider-web-slice.svg" width="40px">
      <i class="h3 ms-1">
        Sp<sub>ider</sub>QL
      </i>
    </a>
    <ul class="nav">

      <li class="nav-item">
        <a class="nav-link" href="{docs_url()}" smooth-link>
          Docs
          <i class="bi bi-journal-text"></i>
        </a>
      </li>
        
    
      <li class="nav-item">
        <a class="nav-link" href="{playground_url()}" smooth-link>
          playground
          <i class="bi bi-joystick"></i>  
        </a>
      </li>
    
    </ul>
  </nav>
  """

func wrapHtml(title, inner: string): string =
  fmt"""
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    
    <title>{title}</title>

    <!-- 3rd party -->


<!--
    <link rel="stylesheet" href="https://bootswatch.com/5/journal/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">

    <script src="https://cdn.jsdelivr.net/npm/unpoly@3.8.0/unpoly.min.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/unpoly@3.8.0/unpoly.min.css">

    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/sql.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/javascript.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/autoit.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/base16/decaf.min.css">
    
    <script type="text/javascript" src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>

    <!-- local -->
-->
    <script defer            type="module"       src="/static/page.js"></script>
    <link   rel="icon"       type="image/x-icon" href="/static/logo.ico">
    <link   rel="stylesheet"                     href="/static/styles.css">

  </head>
  <body class="bg-light">
    <main>
      {navPartial()}
      {inner}
    </main>
  </body>
  </html> 
  """

# ------------------------------ combinators

func formField1(label, icon, name, id, typ: string): string =
  fmt"""
    <fieldset class="my-2">

      <label for="{id}">
        <i class="bi {icon}"></i>
        <i>{label}</i>
      </label>
      
      <input 
        id="{id}" type="{typ}" name="{name}" 
        class="form-control bg-light">

    </fieldset>
  """

func texticon(label, icon: string, tcls = "", icls = "",
    textFirst = true): string =

  let
    t = fmt "<span class=\"{tcls}\">{label}</span>"
    i = fmt "<i class=\"bi {icon} {icls}\"></i>"

  case textFirst
  of true: t & i
  of false: i & t

func lbtnicon(label, icon: string, cls = "", link = ""): string =
  let (tag, attrs) =
    if link == "": ("button", "")
    else: ("a", fmt "smooth-link href=\"{link}\"")

  fmt"""
    <{tag} {attrs} class="btn {cls}">
      {texticon(label, icon, "ms-1 me-2")}
    </{tag}>
  """

# ------------------------------ pages

func landingPageHtml*(): string =
  wrapHtml "landing", """
    <div class="bg-white">
      <div class=" container p-4">
        <h2 class="d-flex justify-content-start">
          Tired of SQL? 😩
        </h2>
        <h3 class="d-flex justify-content-end text-secondary">
          <i>
            No worries, I've got you 👍
          </i>
        </h3>
        <div class="mt-4 d-flex justify-content-center">
          <img src="/static/logo-cc.svg" width="200px">
        </div>
        <h1 class="text-center">
          Sp<sub>ider</sub>QL
        </h1>
      </div>
    </div>

    <div class="bg-light">
      <div id="features" class="container p-4">
        <h2 class="mt-2 mb-5 text-primary">
          <i class="bi bi-magic"></i>
          Features
        </h2>
        
        <div class="row">
          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-braces text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Schema Less</div>
              <p class="text-muted">
                Store your data as simple JSON. 
                Here's <a target="_blank" href="https://www.delphitools.info/2021/06/17/sqlite-as-a-no-sql-database/">how</a>.
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-share text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Embrace Graph</div>
              <p class="text-muted">
                model your data as nodes and edges
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-display text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">UI Interface</div>
              <p class="text-muted">
                we have web front-end too
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-plug text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Various Clients</div>
              <p class="text-muted">
                we have driver for Python, JavaScript, ...
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-cpu text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Don't Have Much Resources?</div>
              <p class="text-muted">
                SpiderQL server doesn't use much RAM! it is based on SQLite
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-speedometer text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Worry About Performance?</div>
              <p class="text-muted">
                it is based on SQLite which has years of development and optimization. 
                read <a target="_blank" href="https://antonz.org/sqlite-is-not-a-toy-database/">SQLite is not a toy database</a>.
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-feather text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Worry About Overhead?</div>
              <p class="text-muted">
                using Nim programming language and simple data structures makes it super lightweight
              </p>
            </div>
          </div>


          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-life-preserver text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Data Loss?</div>
              <p class="text-muted">
                you can set it to backup periodically
              </p>
            </div>
          </div>


          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-puzzle text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Don't Wanna a Server?</div>
              <p class="text-muted">
                it can be imported as a library
              </p>
            </div>
          </div>



          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-rocket-takeoff text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Go <i>Fastttt!</i></div>
              <p class="text-muted">
                best fit for span-size projects and MVPs. the mental friction is almost zero
              </p>
            </div>
          </div>

          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-code-slash text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Query Language</div>
              <p class="text-muted">
                it's intuitive as hell. with respect to <a target="_blank" href="https://antonz.org/fancy-ql/">I don't need your query language</a>.
              </p>
            </div>
          </div>

          
          <div class="d-flex my-4 col-lg-4 col-md-6 col-sm-12">
            <div class="icon mx-2">
              <i class="bi bi-sliders text-primary"></i>
            </div>
            <div class="description">
              <div class="h4">Easily Configurable</div>
              <p class="text-muted">
                you can config it using enviroment variables, CLI flags or simple 
                <a target="_blank" href="https://toml.io/">.toml</a>
                file. 
                you can tweak it the way you want.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="bg-primary">
      <div class="p-4 fs-5 container">
        <header>
          <h2 class="text-white mb-4">
            <i class="bi bi-code-square"></i>
            Query Language
          </h2>

          <blockquote class="blockquote bg-white py-2 px-3 rounded mb-5 shadow-sm">
            <b>
              purpose:
            </b>
            <i>
              find all of the people who acted in "Cobra-11" movie.
            </i>
          </blockquote>
        </header>

        <section class="row d-flex justify-content-center">
          <div class="col-lg-4 col-md-6 col-sm-12">
            <h4 class="text-white">
              SpQL
            </h4>

            <pre><code class="shadow rounded language-autoit">
                
                #acted_in a
                #person   p
                #movie    m
                  = .title "Cobra-11"

                ASK       p>-a->^m
                RETURN    p

              </code></pre>
          </div>

          <div class="col-lg-4 col-md-6 col-sm-12">
            <h4 class="text-white">
              SQL
            </h4>

            <pre><code class="shadow rounded language-sql">
                SELECT    
                  p.*
                FROM 
                  Movie m
                WHERE
                  m.title = 'Cobra-11'
                JOIN
                  Acted_in a
                ON
                  m.id = a.movie_id
                JOIN
                  Person   p
                ON 
                  p.id = a.person_id
              </code></pre>
          </div>
        </section>
      </div>
    </div>
    
    <div class="bg-white">
      <div class="container p-4">
        <h2>
          <i class="bi bi-question-circle"></i>
          FAQ
        </h2>

        <div>
          <h4>
            SpiderQL VS ORM
          </h4>

          <p class="answer">
          </p>
        </div>


        <div>
          <h4>
            What is the story behind SpiderQL?
          </h4>

          <p class="answer">
          </p>
        </div>

        <div>
          <h4>
            Where does the name come from?
          </h4>

          <p class="answer">
          </p>
        </div>

      </div>
    </div>


    <footer class="footer bg-dark text-white">
      <div class="container py-4 px-2">
        <center>
          <div class="my-1">
            built with passion
            🤍
            
            in 
            <a href="https://nim-lang.org/">Nim</a>
            👑
          </div>
          
          <div class="my-1">
            version 0.0.0 - built at 2000/00/00
          </div>
          
        </center>
      </div>
    </footer>

    <div class="bg-black text-black">
      end of page
    </div>
    """

func docsPageHtml*(): string =
  wrapHtml "landing", """
    This is gonna be docs
  """

func databaseListPageHtml*(dbs: seq[(string, BiggestInt)]): string =
  var dbrows = ""
  for (name, size) in dbs:
    add dbrows, fmt"""
      <tr>
        <td>
          <a href="{databaseurl name}" class="text-decoration-none" smooth-link>
            {name}
          </a>
        </td>
        <td>
          {size}
        </td>
      </tr>
      """

  wrapHtml "database list", fmt"""
    <div class="container my-4">

      <div class="my-4">
        <h3>
          <i class="bi bi-collection"></i>
          <span class="mx-2">Databases ({len dbs})</span>
        </h3>

        <table class="table table-hover shadow-sm">
          <thead>
            <tr>
              <th>
                <i class="bi bi-alphabet"></i>
                name
              </th>
              <th>
                <i class="bi bi-sd-card"></i>
                size
              </th>
            </tr>
          </thead>
          <tbody>
            {dbrows}
          </tbody>
        </table>

      </div>
    </div>
  """

func databasePageHtml*( 
  dbname: string,
  size, lastmodif: int,
  nodesInfo, edgesInfo: seq[tuple[tag: string, count: int, doc: JsonNode]],
  tagsOfNodes, tagsOfEdges: int,
  totalNodes, totalEdges: int,
  queryResults, visNodes, visEdges: JsonNode,
  whatSelected: string, 
  selectedData: JsonNode,
  perf: int
): string =
  var
    nodeRows = ""
    edgeRows = ""

  for ni in nodesInfo:
    add nodeRows, fmt"""
      <tr>
        <td>{ni[0]}</td>
        <td>{ni[1]}</td>
        <td><pre><code class="lang-javascript">{pretty ni[2]}</code></pre></td>
      </tr>
    """

  for ei in edgesInfo:
    add edgeRows, fmt"""
      <tr>
        <td>{ei[0]}</td>
        <td>{ei[1]}</td>
        <td><pre><code class="lang-javascript">{pretty ei[2]}</code></pre></td>
      </tr>
    """

  var
    nodeTags: seq[string]
    edgeTags: seq[string]

  for ni in nodesInfo:
    add nodeTags, ni.tag

  for ei in edgesInfo:
    add edgeTags, ei.tag


  let visData = %*{
    "nodes": visNodes,
    "edges": visEdges,
    "vis_data": queryResults,
    "node_tags": nodeTags,
    "edge_tags": edgeTags,
  }

  let entity_id = selectedData{idCol}.getint 0
  let partialSelectionSec = 
    if selectedData.kind == JNull: ""
    else:
      let nodeOptions = 
        if whatSelected == "edge": ""
        else: fmt"""
          <div class="p-1">
            <button class="btn btn-outline-info" onclick="select_as_source({entity_id})">
              select as source   
              <i class="bi bi-box-arrow-right"></i>
            </button>
            <button class="btn btn-outline-info" onclick="select_as_target({entity_id})">
              select as target              
              <i class="bi bi-box-arrow-in-right"></i>
            </button>
          </div>
        """

      fmt"""      
        <div class="p-1">
          <button class="btn btn-outline-primary">
            <i class="bi bi-trash2"></i>
            delete
          </button>
          <button class="btn btn-outline-success" onclick="select_for_update('{whatSelected}', {entity_id})">
            <i class="bi bi-recycle"></i>
            update
          </button>
        </div>
        {nodeOptions}
      """



  wrapHtml fmt"{dbname} DB", fmt"""
    <div class="container my-4">
      <h2 class="mb-4">
        <i class="bi bi-database"></i>
        <span>Database</span>
        <a href="{database_url dbname}" class="text-decoration-none" smooth-link>
          {dbname}
        </a>
      </h2>

      <div>
        <div class="row">
          <section class="col-md-4 col-sm-12 mt-4">
            <div>
              <h4>
                <i class="bi bi-info-square"></i>
                Info
              </h4>
              
              <table class="table table-hover shadow-sm">
                <tbody>
                  <tr>
                    <td>
                      <i class="bi bi-sd-card"></i>
                      <b class="ms-1">database size</b>
                    </td>
                    <td>{size}</td>
                  </tr>
                  <tr>
                    <td>
                      <i class="bi bi-clock-history"></i>
                      <b class="ms-1">last modification</b>
                    </td>
                    <td>{lastmodif}</td>
                  </tr>
                  <tr>
                    <td>
                      <i class="bi bi-eye"></i>
                      <b class="ms-1">is view only?</b>
                    </td>
                    <td>No</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div>
              <h4>
                <i class="bi bi-gear"></i>
                Actions
              </h4>

              <form method="post" action="{database_url dbname}" class="ms-2">
                <button name="backup-database" class="btn btn-outline-primary">
                  <i class="bi bi-floppy"></i>
                  <span>back-up</span>
                </button>

                <button name="remove-database" class="btn btn-outline-primary">
                  <i class="bi bi-trash"></i>
                  <span>remove</span>
                </button>

                <button name="backup-database" class="btn btn-outline-primary">
                  <i class="bi bi-box-seam"></i>
                  <span>change mode</span>
                </button>
              </form>
            </div>
          </section>
          <section class="col-md-8 col-sm-12 mt-4">
            <div>
              <h4>
                <i class="bi bi-truck"></i>
                Back-ups
              </h4>

              <table class="table table-hover shadow-sm">
                <thead>
                  <tr>
                    <th>
                      <i class="bi bi-calendar-event"></i>
                      time
                    </th>
                    <th>
                      <i class="bi bi-sd-card"></i>
                      size
                    </th>
                    <th>
                      <i class="bi bi-cloud-download"></i>
                      download
                    </th>
                  </tr>
                </thead>
                <tbody>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <div class="mt-5">
        <h3 class="d-flex>
          <i class="bi bi-graph-up"></i>
          Analysis
          <hr class="mx-2 w-100 border-2">
        </h3>

        <div class="ms-4">
          <div class="mt-4">
            <h4>
              <i class="bi bi-noise-reduction"></i>
              Nodes
            </h4>

            <section class="mx-2">
              <span>
                all node tags with number of records
              </span>

              <table class="table table-hover shadow-sm">
                <thead>
                  <tr>
                    <th>
                      <i class="bi bi-tags"></i>
                      Tag
                    </th>
                    <th>
                      <i class="bi bi-123"></i>
                      Count
                    </th>
                    <th>
                      <i class="bi bi-diagram-3"></i>
                      Structure
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {nodeRows}
                </tbody>
              </table>
            </section>
          </div>

          <div class="mt-4">
            <h4>
              <i class="bi bi-bounding-box-circles"></i>
              Edges
            </h4>
            
            <section class="mx-2">
              <span>
                all edge tags with number of records
              </span>

              <table class="table table-hover shadow-sm">
                <thead>
                  <tr>
                    <th>
                      <i class="bi bi-tags"></i>
                      Tag
                    </th>
                    <th>
                      <i class="bi bi-123"></i>
                      Count
                    </th>
                    <th>
                      <i class="bi bi-diagram-3"></i>
                      Structure
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {edgeRows}
                </tbody>
              </table>
            </section>
          </div>

          <div class="mt-4">
            <h4>
              <i class="bi bi-plus-slash-minus"></i>
              Summary
            </h4>
            
            <section class="mx-2">
              <span>
                aggregate them all
              </span>

              <table class="table table-hover shadow-sm">
                <thead>
                  <tr>
                    <th>
                    </th>
                    <th>
                      <i class="bi bi-tags"></i>
                      Tags
                    </th>
                    <th>
                      <i class="bi bi-123"></i>
                      Count
                    </th>
                  </tr>
                </thead>
                <tbody>

                  <tr>
                    <th>Nodes</th>
                    <td>{tagsOfNodes}</td>
                    <td>{totalNodes}</td>
                  </tr>
                
                  <tr>
                    <th>Edges</th>
                    <td>{tagsOfEdges}</td>
                    <td>{totalEdges}</td>
                  </tr>

                  <tr>
                    <th>Total</th>
                    <td>{tagsOfNodes+tagsOfEdges}</td>
                    <td>{totalNodes+totalEdges}</td>
                  </tr>
                  
                </tbody>
              </table>
            </section>
          </div>
        </div>
      </div>
      
      
      <div class="row mt-5">
        <section class="col-md-6 col-sm-12">
          <div>
            <h3>
              <i class="bi bi-code-square"></i>
              Query
            </h3>

            <div>
              <h4>
                <i class="bi bi-cloud"></i>
                Saved Queries
              </h4>

              <form>
                <select class="form-select">
                  <option> --custom-- </option>
                  <option>query 1</option>
                  <option>query 2</option>
                  <option>query 3</option>
                </select>

                <button name="use" class="btn btn-sm btn-outline-primary w-100 mt-1">
                  delete selected query
                  <i class="bi bi-trash2"></i>
                </button>
              </form>

              <form>
                <fieldset>
                  <label>
                    <i class="bi bi-fonts"></i>
                    name:
                  </label>
                  <input type="text" name="name" class="form-control" placeholder="like: all people">
                </fieldset>
                <button name="ask" class="btn btn-outline-primary btn-sm w-100 mt-1">
                  <i class="bi bi-plus"></i>
                  Save Query
                </button>
              </form>
            </div>

            <div class="mt-3">
              <h4>
                <i class="bi bi-input-cursor-text"></i>
                Editor
              </h4>
              
              <form action="{database_url dbname}" method="POST" up-submit id="ask-form" up-target="#query-vis, #query-data, #performance_measure">
                <textarea class="form-control editor-height" name="spql_query" lang="sql">
                    #; a b c
                    ask a->^b->c
                    ret 
                      draw! b
                </textarea>

                <fieldset>
                  <label>
                    <i class="bi bi-braces"></i>
                    context:
                  </label>
                  <input type="file" accept=".json" name="node-doc" class="form-control" placeholder="JSON data">
                </fieldset>

                <button name="ask" class="btn btn-outline-primary btn-sm w-100 mt-2">
                  <i class="bi bi-search"></i>
                  Ask
                </button>
              </form>
            </div>
          </div>

          <div class="mt-3" id="performance_measure">
            <h4>
              <i class="bi bi-speedometer2"></i>
              Performance
            </h4>
                        
            <table class="table table-hover shadow-sm">
              <thead>
                <tr>
                  <th>metric</th>
                  <th>time</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    total time
                  </td>
                  <td>
                    {perf}µ
                  </td>
                </tr>
              </tbody>
            </table>

          </div>
        </section>

        <section class="col-md-6 col-sm-12">
          <h3>
            <i class="bi bi-stickies"></i>
            Result
          </h3>
          
          <div id="query-data">
            <pre><code class="compact rounded shadow-sm language-javascript">{pretty queryResults}</code></pre>
          </div>
        </section>
      </div>

      <div class="row mt-3" id="query-vis">
        <section class="col-md-6 col-sm-12 mt-3">
          <h3>
            <i class="bi bi-geo"></i>
            Visualize
          </h3>

          <div vis-graph class="rounded shadow-sm bg-white" style="height: 50vh" up-data='{$visData}'>
          </div>
        </section>

        <section class="col-md-6 col-sm-12 mt-3">
          <div>
            <h4>
              <i class="bi bi-three-dots"></i>
              All
            </h4>

            <div>
              <button class="btn btn-outline-primary">
                <i class="bi bi-trash2-fill"></i>
                delete all
              </button>
            </div>
          </div>

          <div class="mt-3">
            <h4>
              <i class="bi bi-crosshair"></i>
              Focused
            </h4>

            <form id="node-get" action="{database_url dbname}" method="post" up-submit up-target="#partial-data">
              <input type="hidden" name="node-id">
            </form>
            <form id="edge-get" action="{database_url dbname}" method="post" up-submit up-target="#partial-data">
              <input type="hidden" name="edge-id">
            </form>

            <div id="partial-data">
              <pre><code class="compact rounded shadow-sm language-javascript">{pretty selected_data}</code></pre>

              <div class="mt-1">
                {partialSelectionSec}
              </div>
            </div>
          </div>
        </section>
      </div>

      <div class="my-5">
        <h3 class="d-flex">
          <i class="bi bi-plus me-2"></i>
          Add
          <hr class="mx-2 w-100 border-2">
        </h3>

        <div class="row d-flex justify-content-center px-3 pt-2">
          <section class="col-md-6 col-sm-12">
            <h4>
              <i class="bi bi-circle"></i>
              Node
            </h4>

            <form action="{database_url dbname}" method="post" class="ms-2" up-submit>
              <fieldset>
                <label>
                  <i class="bi bi-hash"></i>
                  tag:
                </label>
                <input type="text" name="node-tag" class="form-control" placeholder="like: #person" required>
              </fieldset>
              <fieldset class="invisible d-none d-md-block">
                <label>empty</label>
                <input type="text" class="form-control">
              </fieldset>
              <fieldset>
                <label>
                  <i class="bi bi-braces"></i>
                  JSON document:
                </label>
                <input type="file" accept=".json" name="node-doc" class="form-control" placeholder="JSON data" required>
              </fieldset>
              <button name="add-node" class="btn btn-sm w-100 mt-2 btn-outline-primary text-nowrap">
                <i class="bi bi-plus"></i>
                add
              </button>
            </form>
          </section>

          <section class="col-md-6 col-sm-12">
            <h4>
              <i class="bi bi-share"></i>
              Edge
            </h4>
            
            <form action="{database_url dbname}" method="post" class="ms-2" up-submit>
              <fieldset>
                <label>
                  <i class="bi bi-hash"></i>
                  tag:
                </label>
                <input type="text" name="node-tag" class="form-control" placeholder="like: #owns" required>
              </fieldset>
              <fieldset class="d-flex">
                <fieldset class="w-100">
                  <label>
                    <i class="bi bi-box-arrow-right"></i>
                    source id:
                  </label>
                  <input type="number" min="1" step="1" id="source-id" name="source-id" class="form-control" placeholder="the __id field, like: 31" required>
                </fieldset>
                <fieldset class="w-100">
                  <label>
                    <i class="bi bi-box-arrow-in-right"></i>
                    target id:
                  </label>
                  <input type="number" min="1" step="1" id="target-id" name="target-id" class="form-control" placeholder="the __id field, like: 7" required>
                </fieldset>
              </fieldset>
              <fieldset>
                <label>
                  <i class="bi bi-braces"></i>
                  JSON document:
                </label>
                <input type="file" accept=".json" name="edge-doc" class="form-control" placeholder="JSON data">
              </fieldset>
              <button name="add-edge" class="btn btn-sm w-100 mt-2 btn-outline-primary text-nowrap">
                <i class="bi bi-plus"></i>
                add
              </button>
            </form>
          </section>
        </div>
      </div>

      <div class="my-5">
        <h3 class="d-flex">
          <i class="bi bi-recycle me-2"></i>
          Update
          <hr class="mx-2 w-100 border-2">
        </h3>

        <div class="row d-flex justify-content-center px-3 pt-2">
          <section class="col-md-6 col-sm-12">
            <h4>
              <i class="bi bi-circle"></i>
              Node
            </h4>

            <form action="{database_url dbname}" method="post" class="ms-2" up-submit>
              <fieldset>
                <label>
                  <i class="bi bi-at"></i>
                  id:
                </label>
                <input type="text" min="1" step="1" name="node-id" id="node-id-update" class="form-control" placeholder="">
              </fieldset>
              <fieldset>
                <label>
                  <i class="bi bi-braces"></i>
                  JSON document:
                </label>
                <input type="file" accept=".json" name="node-doc" class="form-control" placeholder="JSON data" required>
              </fieldset>
              <button name="add-node" class="btn btn-sm w-100 mt-2 btn-outline-primary text-nowrap">
                <i class="bi bi-recycle"></i>
                update
              </button>
            </form>
          </section>

          <section class="col-md-6 col-sm-12">
            <h4>
              <i class="bi bi-share"></i>
              Edge
            </h4>
            
            <form action="{database_url dbname}" method="post" class="ms-2" up-submit>
              <fieldset>
                <label>
                  <i class="bi bi-at"></i>
                  id:
                </label>
                <input type="text" min="1" step="1" name="edge-id" id="edge-id-update" class="form-control" placeholder="">
              </fieldset>
              <fieldset>
                <label>
                  <i class="bi bi-braces"></i>
                  JSON document:
                </label>
                <input type="file" accept=".json" name="edge-doc" class="form-control" placeholder="JSON data">
              </fieldset>
              <button name="add-edge" class="btn btn-sm w-100 mt-2 btn-outline-primary text-nowrap">
                <i class="bi bi-recycle"></i>
                update
              </button>
            </form>
          </section>
        </div>
      </div>

      <div class="my-5">
        <h3 class="d-flex">
          <i class="bi bi-collection-play me-2"></i>
          bulk import
          <hr class="mx-2 w-100 border-2">
        </h3>

        <div class="row">
          <section class="col-md-6 col-sm-12 mt-2">
            <form action="{database_url dbname}" method="post" up-submit class="d-flex justify-content-between">
              <input type="file" accept=".json" name="node-doc" class="form-control" placeholder="JSON data" required>
              <button name="add-collection" class="btn btn-outline-primary text-nowrap">
                <i class="bi bi-cloud-upload"></i>
                Upload collection              
              </button>
            </form>
          </section>

          <section class="col-md-6 col-sm-12 mt-2">
            <div class="alert alert-info">
              <strong>Heads up!</strong> 
              This 
              <a href="#" class="alert-link">alert needs your attention</a>
              , but it's not super important.
            </div>
          </section>
        </div>
      </div>

    </div>
  """
