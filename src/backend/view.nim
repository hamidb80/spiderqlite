import std/[strformat]

# ------------------------------ combinators

proc redirectingHtml*(link: string): string =
  fmt"""
    <a href="{link}" smooth-link redirect >
      redirecting ...
    </a>
  """


func navPartial: string =
  """
  <nav class="navbar navbar-expand-lg bg-primary px-3 py-1" data-bs-theme="dark">
    <a class="text-white mb-1 text-decoration-none" href="/" smooth-link>
      <img src="/static/spider-web-slice.svg" width="40px">
      <i class="h3  ms-1">
        Sp<sub>ider</sub>QL
      </i>
    </a>
    <ul class="nav">
    
      <li class="nav-item">
        <a class="nav-link" href="/docs/" smooth-link>
          Docs
          <i class="bi bi-journal-text"></i>
        </a>
      </li>
          
      <li class="nav-item">
        <a class="nav-link" href="/sign-in/" smooth-link>
          sign-in
          <i class="bi bi-box-arrow-in-right"></i>
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

    <link rel="stylesheet" href="https://bootswatch.com/5/journal/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">

    <script src="https://cdn.jsdelivr.net/npm/unpoly@3.8.0/unpoly.min.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/unpoly@3.8.0/unpoly.min.css">


    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/sql.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/autoit.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/base16/decaf.min.css">


    <script src="/static/page.js" defer></script>


    <link rel="icon" type="image/x-icon" href="/static/logo.ico">


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

func texticon(label, icon: string, tcls = "", icls = "", textFirst = true): string =
    
  let 
    t = fmt "<span class=\"{tcls}\">{label}</span>"
    i = fmt "<i class=\"bi {icon} {icls}\"></i>"

  case textFirst
  of true:  t & i
  of false: i & t

func lbtnicon(label, icon: string, cls = "", link = ""): string = 
  let (tag, attrs) = 
    if link == "": ("button", "")
    else:          ("a"     , fmt "smooth-link href=\"{link}\"")

  fmt"""
    <{tag} {attrs} class="btn {cls}">
      {texticon(label, icon, "ms-1 me-2")}
    </{tag}>
  """

# ------------------------------ pages

func landingPageHtml*: string =
  wrapHtml "landing", """
    <style>
      .row .bi {
        font-size: 40px;
      }

      .row .icon {
        margin-top: -10px;
      }

      pre {
        overflow: visible;
      }
    </style>


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
      <div class="container p-4">
        <div class="aa-product-details section" id="features">
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
                <i class="bi bi-people text-primary"></i>
              </div>
              <div class="description">
                <div class="h4">Have Multiple Apps?</div>
                <p class="text-muted">
                  is supports mutli user
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
                  you can set it to backup priodically
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
                  best fit for small-size projects and MVPs. the mental friction is almost zero
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
    </div>

    <div class="bg-primary">
      <div class="p-4 mx-0 row d-flex justify-content-center fs-5">

        <h2 class="text-white mb-4">
          Query Language
        </h2>

        XXX select option to see more examples

        <blockquote class="blockquote bg-white py-2 px-3 rounded mb-5 shadow-sm">
          <b>
            purpose:
          </b>
          <i>
            find all of the people who acted in "Cobra-11" movie.
          </i>
        </blockquote>

        <div class="col-lg-4 col-md-6 col-sm-12">

          <h4 class="text-white">
            SpQL
          </h4>

          <pre><code class="shadow rounded language-autoit">
              
              @acted_in a
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
      </div>
    </div>

    
    <div class="bg-white">
      <div class="container p-4">
        <h3>
          Frequently Asked Questions :: FAQ
        </h3>
      </div>
    </div>


    <footer class="footer bg-dark text-white">
      <div class="container py-4 px-2">
        <center>
          <div class="my-1">
            created with passion
            🤍
          </div>
          
          <div class="my-1">
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


const 
  signinIcon = "bi-box-arrow-in-right"
  signupIcon = "bi-person-add"

func signinupPageHtml*(title, icon: string, errors: seq[string], inputs, btns: string): string =
  var errorsAcc = ""
  for e in errors:
    add errorsAcc, "<li>"
    add errorsAcc, e
    add errorsAcc, "</li>"


  wrapHtml title, fmt"""
    <div class="card mt-4 mx-auto shadow-sm" style="max-width: 600px;">
      <div class="card-header">
        <h3>
          {texticon(title, icon, "", "me-3", false)}
        </h3>
      </div>
      <div class="card-body">
        <form action="." up-submit method="POST>
          {inputs}
          <ul>{errorsAcc}</ul>
          <div class="d-flex justify-content-center mt-4">{btns}</div>
        </form>
      </div>
    </div>
  """


func signinPageHtml*(errors: seq[string]): string =
  signinupPageHtml "Sign In", signinIcon, errors, fmt"""
          {formField1("username", "bi-at",       "username", "inp-uname", "text")}
          {formField1("passowrd", "bi-asterisk", "password", "inp-passw", "password")}
  """, fmt"""
          {lbtnicon("sign up", signupIcon, "btn-outline-primary mx-1", "/sign-up/")}
          {lbtnicon("sign in", signinIcon, "btn-primary         mx-1")}
  """

func signupPageHtml*(errors: seq[string]): string =
  signinupPageHtml "Sign up", signupIcon, errors, fmt"""
          {formField1("username", "bi-at",       "username", "inp-uname", "text")}
          {formField1("password", "bi-asterisk", "password", "inp-passw", "password")}
  """, fmt"""
          {lbtnicon("sign up", signupIcon, "btn-primary         mx-1")}
          {lbtnicon("sign in", signinIcon, "btn-outline-primary mx-1", "/sign-in/")}
  """


func profilePageHtml*(): string = 
  wrapHtml "profile", """
    your profile here
  """
