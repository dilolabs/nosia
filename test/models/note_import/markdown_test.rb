require "test_helper"

class NoteImport::MarkdownTest < ActiveSupport::TestCase
  test "resolves wiki targets literally and Markdown targets through one URL decode" do
    paths = [ "Travail/Plan.md", "Réunion.md", "A%20B.md", "A B.md" ]
    prepared = prepare(paths, <<~MD)
      [[Réunion|Voir]] [[A%20B]] [Space](../A%20B.md)
      `[[Réunion]]` ![[diagram.png]]
    MD

    assert_equal "Travail/Plan.md", prepared.path
    assert_equal "Travail", prepared.directory
    assert_equal "Plan", prepared.title
    fragment = rendered(prepared, paths)
    assert_equal [ [ "/accounts/1/notes/11", "Voir" ], [ "/accounts/1/notes/12", "A%20B" ],
      [ "/accounts/1/notes/13", "Space" ] ], links(fragment)
    assert_equal "[[Réunion]]", fragment.at_css("code").text
    assert_includes fragment.text, "![[diagram.png]]"
    assert_equal 0, prepared.warnings.fetch(:count)
  end

  test "preserves formatted labels and renders forward mutual and self links without mutating the URLs" do
    paths = [ "Plan.md", "Folder/Next.MD" ]
    converter = NoteImport::Markdown.new(paths)
    first = converter.prepare(paths.first, "[[*Missing*]] [**Next**](./Folder/Next.md) [Self](Plan.MD)")
    second = converter.prepare(paths.last, "[[Plan]] [[Folder/Next.md|Self]]")
    urls = urls_for(paths).freeze
    html = first.render(urls)

    assert_equal "", first.directory
    assert_equal "/accounts/1/notes/11", Nokogiri::HTML5.fragment(html).at_css("a > strong").parent["href"]
    assert_equal [ [ "/accounts/1/notes/11", "Next" ], [ "/accounts/1/notes/10", "Self" ] ], links(Nokogiri::HTML5.fragment(html))
    assert_equal [ [ "/accounts/1/notes/10", "Plan" ], [ "/accounts/1/notes/11", "Self" ] ], links(rendered(second, paths))
    assert_includes first.render(urls.merge("Folder/Next.MD" => "/accounts/1/notes/21")), 'href="/accounts/1/notes/21"'
    assert_equal html, first.render(urls)
    assert_equal html.bytesize, first.render(urls).bytesize
  end

  test "compares names in NFC without folding case and never guesses ambiguous names" do
    paths = [ "Travail/Plan.md", "Réunion.md", "Root/Topic.md", "Other/Topic.md", "Clash.md", "Clash.MD" ]
    prepared = prepare(paths, "[[Re\u0301union]] [[réunion|Wrong case]] [[Root/Topic.MD|Qualified]] " \
      "[[Topic|Ambiguous]] [[Clash.md|Same path]] [Clash](../Clash.md) [NFC](../Re%CC%81union.MD)")
    fragment = rendered(prepared, paths)

    assert_equal [ "/accounts/1/notes/11", "/accounts/1/notes/12", "/accounts/1/notes/11" ], links(fragment).map(&:first)
    assert_includes fragment.text, "Wrong case"
    assert_includes fragment.text, "réunion"
    assert_equal 4, prepared.warnings.fetch(:count)
    assert_equal [ "réunion", "Topic", "Clash.md", "../Clash.md" ], prepared.warnings.fetch(:examples).pluck(:target)
  end

  test "refuses unsupported or invalid local destinations and reports their original targets" do
    paths = [ "Folder/Plan.md", "a+b.md", "a%20b.md", "a%QZ.md", "b.md", "Folder/b.md" ]
    prepared = prepare(paths, <<~MD)
      [plus](../a+b.MD) [once](../a%2520b.md) [local](.././Folder/../b.md)
      [bad](../a%QZ.md) [invalid utf8](../%FF.md) [slash](..%2Fb.md) [backslash](..%5Cb.md)
      [up](../../b.md) [absolute](/b.md) [empty](../Folder//b.md)
      [anchor](../b.md#Heading) [query](../b.md?q=1) [block](#^block) [non-md](diagram.png)
      [[b#Heading|Heading]] [[b^block|Block]] [[Folder//b|Empty]] [[../b|Up]]
    MD
    fragment = rendered(prepared, paths)

    assert_equal [ "/accounts/1/notes/11", "/accounts/1/notes/12", "/accounts/1/notes/14" ], links(fragment).map(&:first)
    assert_includes fragment.text, "invalid utf8"
    assert_includes fragment.text, "../%FF.md"
    assert_includes fragment.text, "b^block"
    assert_equal 15, prepared.warnings.fetch(:count)
    assert_equal %w[../a%QZ.md ../%FF.md ..%2Fb.md ..%5Cb.md ../../b.md /b.md ../Folder//b.md ../b.md#Heading
      ../b.md?q=1 #^block diagram.png b#Heading b^block Folder//b ../b], prepared.warnings.fetch(:examples).pluck(:target)
  end

  test "binds wiki links through physical line breaks tabs indentation and nested inline formatting" do
    paths = [ "Plan.md", "A B.md", "A%20B.md" ]
    source = "  é *[[A B|First]]*\r\n   [[A%20B|Second]]\r\n>\té [[A B|Third]]\r" \
      "-\t**[[A%20B|Fourth]]**\nword\t[[A B|Fifth]]\n\n" \
      "[[A%20B|Multi\nline]] [[A B|Same]] [[A%20B|Same]]\n\n" \
      "| Header |\n|---|\n| [[A B\\|Cell]] [[A%20B]] |"
    fragment = rendered(prepare(paths, source), paths)

    assert_equal [ 11, 12, 11, 12, 11, 12, 11, 12, 11, 12 ].map { |id| "/accounts/1/notes/#{id}" }, links(fragment).map(&:first)
    assert_equal "First", fragment.at_css("em > a").text
    assert_equal "Fourth", fragment.at_css("strong > a").text
    assert_equal "Cell", fragment.at_css("table td > a").text
  end

  test "a wiki target on the next line remains inert without losing other literal wiki bindings" do
    paths = [ "Plan.md", "A B.md", "A%20B.md", "Réunion.md" ]
    source = "é [[A B|Same]] [[\r\nRéunion|Multiline]] [[A%20B|Same]] [[Réunion|Fin]]"
    prepared = prepare(paths, source)
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "Same" ], [ "/accounts/1/notes/12", "Same" ],
      [ "/accounts/1/notes/13", "Fin" ] ], links(fragment)
    assert_equal [ "\nRéunion" ], prepared.warnings.fetch(:examples).pluck(:target)
    assert_includes fragment.text, "Multiline"
  end

  test "a blockquote marker change does not shift either identical-looking wiki destination" do
    paths = [ "Plan.md", "A B.md", "A%20B.md", "Réunion.md" ]
    source = "> é [[A B|Same]] [[\n> Réunion|Multiline]] [[A%20B|Same]] [[Réunion|Fin]]"
    prepared = prepare(paths, source)
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "Same" ], [ "/accounts/1/notes/12", "Same" ],
      [ "/accounts/1/notes/13", "Fin" ] ], links(fragment.at_css("blockquote"))
    assert_equal 1, prepared.warnings.fetch(:count)
    assert_includes fragment.text, "Multiline"
  end

  test "wiki destinations between two unrelated marker mismatches are still verified" do
    paths = [ "Plan.md", "A B.md", "A%20B.md", "Réunion.md" ]
    prepared = prepare(paths, <<~MD)
      > é [[
      > Réunion|First]]

      [[A%20B]] [[A B|Same]] [[A%20B|Same]] [[Absent name|Unavailable]]

      > É [[
      > Réunion|Last]]
    MD
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/12", "A%20B" ], [ "/accounts/1/notes/11", "Same" ],
      [ "/accounts/1/notes/12", "Same" ] ], links(fragment)
    assert_equal 3, prepared.warnings.fetch(:count)
    assert_equal "Absent name", prepared.warnings.fetch(:examples).second.fetch(:target)
    assert_empty fragment.css("[data-sourcepos]")
    assert_includes fragment.text, "First"
    assert_includes fragment.text, "Last"
  end

  test "embed captions are entirely inert without touching code or escaped embed syntax" do
    paths = [ "Plan.md", "Target.md" ]
    source = <<~'MD'
      Before ![[Diagram.png|caption <person@example.org> and [reference](Target.md)]] after
      [Outside](https://example.org/notes)
      [[Target]] `![[Diagram.png|<code@example.org>]]`

      \!\[[Diagram.png|<escaped@example.org>]] \![[Target|Escaped bang]]

      ```
      ![[Diagram.png|<fenced@example.org>]]
      ```
    MD
    prepared = prepare(paths, source)
    fragment = rendered(prepared, paths)

    assert_equal [ [ "https://example.org/notes", "Outside" ], [ "/accounts/1/notes/11", "Target" ],
      [ "mailto:escaped@example.org", "escaped@example.org" ], [ "/accounts/1/notes/11", "Escaped bang" ] ], links(fragment)
    assert_includes fragment.text, "Before ![[Diagram.png|caption <person@example.org> and [reference](Target.md)]] after"
    assert_equal [ "![[Diagram.png|<code@example.org>]]", "![[Diagram.png|<fenced@example.org>]]\n" ], fragment.css("code").map(&:text)
    assert_empty fragment.css("img, picture, video, audio, source, embed, object, a a")
    assert_equal 0, prepared.warnings.fetch(:count)
  end

  test "embed detection does not change an external autolink with brackets in its URL" do
    paths = [ "Plan.md" ]
    prepared = prepare(paths, "Autolink: https://example.org/![[Diagram]] and <outside@example.org>")
    fragment = rendered(prepared, paths)

    assert_equal [ [ "https://example.org/!%5B%5BDiagram%5D%5D", "https://example.org/![[Diagram]]" ],
      [ "mailto:outside@example.org", "outside@example.org" ] ], links(fragment)
  end

  test "an embed preserves the punctuation boundary for an adjacent external autolink" do
    paths = [ "Plan.md" ]
    prepared = prepare(paths, "![[Diagram.png]]https://example.org and ![[Map.png|<person@example.org>]]https://example.net")
    fragment = rendered(prepared, paths)

    assert_equal [ [ "https://example.org", "https://example.org" ], [ "https://example.net", "https://example.net" ] ], links(fragment)
    assert_includes fragment.text, "![[Diagram.png]]https://example.org"
    assert_includes fragment.text, "![[Map.png|<person@example.org>]]https://example.net"
    assert_empty fragment.css("img, object, embed, a a")
  end

  test "an embed inside a link label remains inert and the original destination stays readable" do
    paths = [ "Plan.md", "Target.md" ]
    prepared = prepare(paths, "[Before ![[Diagram.png|caption]] after](Target.md) [[Target|Outside]]")
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "Outside" ] ], links(fragment)
    assert_includes fragment.text, "Before ![[Diagram.png|caption]] after (Target.md)"
  end

  test "does not convert escaped or code wiki text or create nested anchors" do
    paths = [ "Plan.md", "Target.md" ]
    source = <<~'MD'
      \[[Target]] `[[Target]]` [before [[Target]] after](Target.md)
      ![[Target]]

          [[Target]]

      ```
      [[Target]]
      [Go](Target.md)
      ```
    MD
    prepared = prepare(paths, source)
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "before [[Target]] after" ] ], links(fragment)
    assert_equal [ "[[Target]]", "[[Target]]\n", "[[Target]]\n[Go](Target.md)\n" ], fragment.css("code").map(&:text)
    assert_includes fragment.text, "![[Target]]"
    assert_equal 0, prepared.warnings.fetch(:count)
  end

  test "Markdown links inside image labels do not shift the following real links" do
    paths = [ "Plan.md", "Target.md", "Other.md" ]
    prepared = prepare(paths, "![a [hidden](Other.md)](image.png) [Real](Target.md) [Reference][r]\n\n[r]: Other.md")
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "Real" ], [ "/accounts/1/notes/12", "Reference" ] ], links(fragment)
    assert_includes fragment.text, "a hidden"
    assert_equal 0, prepared.warnings.fetch(:count)
  end

  test "unresolved literal wiki targets are reported even when an anchor has no label" do
    paths = [ "Plan.md", "A B.md", "A&amp;B.md" ]
    target = "a" * 1_000
    prepared = prepare(paths, "[[A B]] [[#{target}]] [[A&amp;B|Literal]] [[|Missing]] [[Absent|]] [[A\\]B|Escaped]]")
    fragment = rendered(prepared, paths)

    assert_equal [ [ "/accounts/1/notes/11", "A B" ], [ "/accounts/1/notes/12", "Literal" ] ], links(fragment)
    assert_equal [ target.byteslice(0, 512), "", "Absent", 'A\]B' ], prepared.warnings.fetch(:examples).pluck(:target)
    assert_includes fragment.text, "Absent"
  end

  test "a markdown filename with an empty stem cannot resolve as its directory name" do
    paths = [ "Plan.md", "Folder/.md" ]
    prepared = prepare(paths, "[[Folder|Folder name]] [[Folder/.md|Empty stem]]")

    assert_empty links(rendered(prepared, paths))
    assert_equal [ "Folder", "Folder/.md" ], prepared.warnings.fetch(:examples).pluck(:target)
  end

  test "preserves supported external links and makes raw HTML and Markdown media inert before sanitizing" do
    paths = [ "Plan.md", "Target.md" ]
    prepared = prepare(paths, <<~MD)
      [site](https://example.com/read?q=1&lang=fr#top) <person@example.com>
      [unsafe local](file:///target.md) [protocol relative](//example.com/target.md)
      [go](Target.md) ![diagram](https://example.com/diagram.png)

      <img src="https://example.com/raw.png" alt="Raw image">

      Text <a data-wikilink="true" href="Target.md">Raw link</a>.
    MD
    html = prepared.render(urls_for(paths))
    fragment = Nokogiri::HTML5.fragment(html)
    expected = [ [ "https://example.com/read?q=1&lang=fr#top", "site" ],
      [ "mailto:person@example.com", "person@example.com" ], [ "/accounts/1/notes/11", "go" ] ]

    assert_equal expected, links(fragment)
    assert_empty fragment.css("img, picture, iframe, video, audio, source, embed, object, [data-wikilink]")
    assert_includes fragment.text, "diagram"
    assert_includes fragment.text, '<img src="https://example.com/raw.png" alt="Raw image">'
    assert_includes fragment.text, '<a data-wikilink="true" href="Target.md">Raw link</a>'
    sanitized = Note::Body.new(html).html
    assert_equal expected, links(Nokogiri::HTML5.fragment(sanitized))
    assert_equal sanitized, Note::Body.new(sanitized).html
  end

  test "keeps front matter as readable escaped code without interpreting it" do
    paths = [ "Plan.md", "Target.md" ]
    source = "---\r\ntitle: <Example>\r\nref: '[[Target]]'\r\ntags: [#hidden]\r\n---\r\n\r\n# Heading\r\n\r\n[[Target]] #visible"
    prepared = prepare(paths, source)
    html = prepared.render(urls_for(paths))
    body = Note::Body.new(html)

    [ html, body.html ].each do |content|
      fragment = Nokogiri::HTML5.fragment(content)
      assert_equal "---\ntitle: <Example>\nref: '[[Target]]'\ntags: [#hidden]\n---\n", fragment.at_css("pre > code").text
      assert_equal "Heading", fragment.at_css("h1").text
      assert_equal [ [ "/accounts/1/notes/11", "Target" ] ], links(fragment)
    end
    assert_equal [ "visible" ], body.tag_keys
  end

  test "counts every missing target but shares the example cap across notes" do
    paths = [ "One.md", "Two.md", "Three.md" ]
    target = "a#{"é" * 300}.md"
    converter = NoteImport::Markdown.new(paths)
    first = converter.prepare(paths.first, "[One](#{target})\n" * 60)
    second = converter.prepare(paths.second, "[[Missing]]\n" * 60)
    third = converter.prepare(paths.last, "[[Other]]")

    assert_equal [ 60, 60, 1 ], [ first, second, third ].map { |doc| doc.warnings.fetch(:count) }
    assert_equal [ 60, 40, 0 ], [ first, second, third ].map { |doc| doc.warnings.fetch(:examples).size }
    example = first.warnings.fetch(:examples).first
    assert_equal "One.md", example.fetch(:path)
    assert_equal "a#{"é" * 255}", example.fetch(:target)
    assert_equal 511, example.fetch(:target).bytesize
    assert example.fetch(:target).valid_encoding?
    assert_includes rendered(first, paths).text, target
  end

  test "enforces the rendered byte limit before and after filling in URLs" do
    paths = [ "Plan.md", "Target.md" ]
    assert_raises(NoteImport::Invalid) { prepare(paths, "&" * 1.megabyte) }.tap do |error|
      assert_equal :rendered_file_size_exceeded, error.code
      assert_equal paths.first, error.path
    end

    prepared = prepare(paths, "[[Target]]")
    html = prepared.render(urls_for(paths))
    assert_operator prepared.prepared_bytesize, :<=, html.bytesize
    assert_equal 64.megabytes, NoteImport::Markdown::MAX_TOTAL_RENDERED_BYTES
    assert_raises(NoteImport::Invalid) do
      prepared.render("Target.md" => "/" + "a" * 4.megabytes)
    end
    assert_equal html, prepared.render(urls_for(paths))
  end

  private
    def prepare(paths, source)
      NoteImport::Markdown.new(paths).prepare(paths.first, source)
    end

    def rendered(prepared, paths)
      Nokogiri::HTML5.fragment(prepared.render(urls_for(paths)))
    end

    def urls_for(paths)
      paths.each_with_index.to_h { |path, index| [ path, "/accounts/1/notes/#{index + 10}" ] }
    end

    def links(fragment)
      fragment.css("a").map { |anchor| [ anchor["href"], anchor.text ] }
    end
end
