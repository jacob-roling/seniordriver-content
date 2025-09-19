# Dump WordPress JSON endpoint to local JSON files.
def "main dump" [
  json_endpoint: string # Example: https://mywpsite.com/wp-json/wp/v2.
  --out: string = "." # Output directory.
  --content: string = "posts,media,categories,tags,users,comments" # A comma-separated list of content types. Each one of [posts, media, categories, tags, users, comments].
  --ignore_fields: string = "_links" # A comma-separated list of fields to ignore.
] {
  let out_file = $"(date now | format date "%Y-%m-%d")-dump.json"
  let out_dir = $out
  let out_path = [$out_dir, $out_file] | path join
  let dotenv = dot-env
  let token = ([$dotenv.WP_USERNAME, $dotenv.WP_PASS] | str join ":") | encode base64
  
  let default_headers = {
    "Accept": "application/json"
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0"
  }

  let custom_headers = {
    Authorization: (["Basic", $token] | str join " ")
  }
  
  let content_types = $content | split row "," | each { |v| $v | str trim }
  let ignore_fields = $ignore_fields | split row "," | each { |v| $v | str trim }
  let json_endpoint = $json_endpoint | url parse

  let request_headers = $default_headers | merge $custom_headers

  let data = $content_types
    | reduce -f {} { 
      |type, data| $data | insert $type (do {
      let content_endpoint = $json_endpoint | update path { |prev| $prev.path | path join $type } | url join
      let first_page_url = ([$content_endpoint, ({ page: 1 per_page: 100 } | url build-query)] | str join '?')
      let first_page = http get -f -H $request_headers $first_page_url
      let first_page_response_headers = $first_page.headers.response | transpose -rd
      let total_pages = $first_page_response_headers | get x-wp-totalpages | into int
      let page_urls = 1..$total_pages | each { |n| [$content_endpoint, ({ page: $n per_page: 100 } | url build-query)] | str join '?' }
      let pages = $page_urls | par-each { |url| http get -H $request_headers $url } | flatten | reject ...$ignore_fields
      return $pages
    })
  }

  ensure_file $out_path
  $data | save -f $out_path
  return
}

def main [dump_file: string] {
  let data = $dump_file | open
  let all_data = $data | values | flatten
  let old_ids = $all_data | get id | uniq | each { |id| $id | into string }
  let id_map = $old_ids
    | chunks 100
    | par-each { |chunk| $chunk | each { |id| [$id, (random uuid -v 7)] } }
    | flatten
    | into record
  
    # pandoc -f html+native_divs+native_spans -t gfm+pipe_tables --wrap=preserve --lua-filter=filter.lua
  let $posts = $data | get "posts"
    | first 10
    | select id status date_gmt modified_gmt slug title featured_media categories tags author content
    | update id { |row| $id_map | get ($row.id | into string) }
    | update featured_media { |row| $id_map | get ($row.featured_media | into string) }
    | update categories { |row| $row.categories | each { |id| $id_map | get ($id | into string) } }
    | update tags { |row| $row.tags | each { |id| $id_map | get ($id | into string) } }
    | update date_gmt {|row| $row.date_gmt | into datetime | format date "%+" }
    | update modified_gmt {|row| $row.modified_gmt | into datetime | format date "%+" }
    | update title {|row| $row.title.rendered }
    | update content {|row| $row.content.rendered | str trim }
    | update author {|row| [($id_map | get ($row.author | into string))] }
    | rename id status published modified slug title featuredMediaId categoryIds tagIds authorIds content
    | insert description ""
    | move description --after title
  
  # let $categories = $data | get "categories"
  #   | select id parent slug name description
  #   | update id { |row| $id_map | get ($row.id | into string) }
  #   | update parent { |row| if $row.parent == 0 { null } else { $id_map | get ($row.parent | into string) } }
  
  # let $tags = $data | get "tags"
  #   | select id slug name
  #   | update id { |row| $id_map | get ($row.id | into string) }

  # let $users = $data | get "users"
  #   | select id slug name description
  #   | update id { |row| $id_map | get ($row.id | into string) }
  #   | insert email ""
  #   | move email --after name
  #   | insert content ""
  
  # let $comments = $data | get "comments"
  #   | where status == "approved"
  #   | select id post date_gmt author content
  #   | update id { |row| $id_map | get ($row.id | into string) }
  #   | update post { |row| $id_map | get ($row.post | into string) }
  #   | update author { |row| $id_map | get ($row.author | into string) }
  #   | update date_gmt {|row| $row.date_gmt | into datetime | format date "%+" }
  #   | update content {|row| $row.content.rendered | str trim | pandoc -f html+native_divs+native_spans -t gfm --wrap=none --lua-filter=filter.lua }
  #   | rename id subjectId published authorId content

  rm -rf posts
  $posts | par-each { |data| do {
    let path = $"./posts/($data.id).json"
    ensure_file $path
    $data | save -f $path
  } }

  # $categories | par-each { |data| do {
  #   let path = $"./categories/($data.id).json"
  #   ensure_file $path
  #   $data | save -f $path
  # } }

  # $tags | par-each { |data| do {
  #   let path = $"./tags/($data.id).json"
  #   ensure_file $path
  #   $data | save -f $path
  # } }

  # $users | par-each { |data| do {
  #   let path = $"./users/($data.id).json"
  #   ensure_file $path
  #   $data | save -f $path
  # } }

  # $comments | par-each { |data| do {
  #   let path = $"./comments/($data.id).json"
  #   ensure_file $path
  #   $data | save -f $path
  # } }

  return
}

def dot-env [path:string = ".env"] {
  open $path
    | lines
    | split row "="
    | chunks 2
    | reduce -f {} { 
      |row, r| $r | insert $row.0 ($row.1 | str trim)
    }
}

def map-get [id] { $in | get ($id | into string) }

def fetch_url [
  url: string
  custom_headers: record = {}
] {
  let default_headers = {
    "Accept": "application/json"
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0"
  }

  let res = http get -f -H ($default_headers | merge $custom_headers) $url

  return $res
}

def get_endpoint [taxonomy:string] {
  $"($in)/wp-json/wp/v2/($taxonomy)"
}

def paginate [pages:int] {
  return 1..$pages | each { |n| [$in, ({ page: $n } | url build-query)] | str join '&' }
}

def ensure_file [path:string] {
  mkdir ($path | path dirname)
  touch $path
}

def format_categories [out:string id_map] {
  let path = $"($out)/categories.json"
  ensure_file $path
  glob $"($out)/categories/*.json" 
    | each { |table| open $table }
    | flatten
    | update id { |row| $id_map | map-get $row.id }
    | save -f $path
}

def format_comments [out:string id_map] {
  let path = $"($out)/comments.json"
  ensure_file $path
  glob $"($out)/comments/*.json" 
    | each { |table| open $table }
    | flatten
    | update id { |row| $id_map | map-get $row.id }
    | update parent {
      |row| if $row.parent == 0 {
        $id_map | map-get $row.post
      } else {
        $id_map | map-get $row.parent
      }
    }
    | reject post
    | rename id subject author_name date_gmt content
    | save -f $path
}

def format_tags [out:string id_map] {
  let path = $"($out)/tags.json"
  ensure_file $path
  glob $"($out)/tags/*.json" 
    | each { |table| open $table }
    | flatten
    | update id { |row| $id_map | map-get $row.id }
    | save -f $path
}

# | select id date_gmt modified_gmt slug status link title content excerpt _embedded
# | update title {|row| $row.title.rendered }
# | update content {|row| $row.content.rendered }
# | update excerpt {|row| $row.excerpt.rendered }

# let chunk = $resp.body
#   | from json
#   | select id date_gmt slug title content _embedded
#   | update title {|row| $row.title.rendered }
#   | update content {|row| $row.content.rendered | pandoc -f html -t gfm --wrap=none --lua-filter=./scripts/figure_min.lua | str trim }
  # | rename pubDate slug title content featuredMedia
# $chunk | first | select id title content | save -f post.json