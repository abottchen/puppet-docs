class String
  def html_safe!
    self
  end unless "post 9415935902f120a9bac0bfce7129725a0db38ed3".respond_to?(:html_safe!)
end

module PuppetGuides
  class Generator
    attr_reader :output, :view_path, :view, :guides_dir

    class MissingPrologueError < ::ArgumentError; end

    def initialize(output = nil)
      @guides_dir = File.join(File.dirname(__FILE__), '..', '..')

      @output = output || File.join(@guides_dir, "output")

      unless ENV["ONLY"]
        FileUtils.rm_r(@output) if File.directory?(@output)
        FileUtils.mkdir(@output)
      end

      @view_path = File.join(@guides_dir, "source")
    end

    def generate
      guides = Dir.entries(view_path).find_all {|g| g =~ /^[^#]+\.markdown(?:\.erb)?$/ }

      if ENV["ONLY"]
        only = ENV["ONLY"].split(",").map{|x| x.strip }.map {|o| "#{o}.markdown" }
        guides = guides.find_all {|g| only.include?(g) }
        puts "GENERATING ONLY #{guides.inspect}"
      end

      guides.each do |guide|
        generate_guide(guide)
      end

      # Copy images and css files to html directory
      FileUtils.cp_r File.join(guides_dir, 'images'), File.join(output, 'images')
      FileUtils.cp_r File.join(guides_dir, 'files'), File.join(output, 'files')
    end

    def generate_guide(guide)
      guide =~ /(.*?)\.markdown(?:\.erb)?$/
      name = $1

      puts "Generating #{name}"

      file = File.join(output, "#{name}.html")
      File.open(file, 'w') do |f|
        @view = ActionView::Base.new(view_path)
        @view.extend(Helpers)

        if guide =~ /\.markdown\.erb$/
          # Generate the erb pages with markdown formatting - e.g. index/authors
          result = view.render(:layout => 'layout', :file => guide)
          f.write markdown(result)
        else
          body = File.read(File.join(view_path, guide))
          title, body = set_header_section(name, body, @view)
          unless title && body
            puts "Skipping..."
            next
          end
          body = set_index(title, body, @view)
          body = add_extras(body)
          result = view.render(:layout => 'layout', :text => markdown(body, true).html_safe!)
          f.write result
          warn_about_broken_links(result) if ENV.key?("WARN_BROKEN_LINKS")
        end
      end
    end

    def set_header_section(name, body, view)
      header, new_body = body.split(/\*\s+\*\s+\*/, 2)
      if new_body
        if header =~ /^(\S[^\r\n]+)\r?\n-+\s*$/ms
          page_title = $1.strip
        else
          page_title = name.titleize
        end
        header = markdown(header)
        view.content_for(:page_title) { page_title.html_safe! }
        view.content_for(:header_section) { header.html_safe! }
        [page_title, new_body]
      else
        puts "Did not provide a prologue separator."
        false
      end
    end

    def set_index(title, body, view)
      index = <<-INDEX
      <div id="subCol">
        <h3 class="chapter"><img src="images/chapters_icon.gif" alt="" />Contents</h3>
        <ol class="chapters">
      INDEX

      html = Maruku.new("#{title}\n#{'=' * title.size}\n\n#{body}\n\n* Create TOC\n{:toc}").to_html_document
      doc = Nokogiri(html)
      toc = doc.css('.maruku_toc')
      index << toc.css('ul').first.children.to_s

      index << '</ol>'
      index << '</div>'

      view.content_for(:index_section) { index.html_safe! }

      body
    end

    def markdown(body, include_settings = false)
      body = settings_content + body if include_settings
      Maruku.new(body).to_html
    end

    def add_extras(body)
      body.gsub(/^(NOTE|INFO|WARNING)(?:\.|\:)(.*?)(?:\r?\n){2,}/ms) do |m|
        css_class = $1.downcase
        result = "<div class='#{css_class}'>"
        result << markdown($2.strip)
        result << "</div>\n\n"
        result
      end
    end

    def warn_about_broken_links(html)
      anchors = extract_anchors(html)
      check_fragment_identifiers(html, anchors)
    end
    
    def extract_anchors(html)
      # Markdown generates headers with IDs computed from titles.
      anchors = Set.new
      html.scan(/<h\d\s+id="([^"]+)/).flatten.each do |anchor|
        if anchors.member?(anchor)
          puts "*** DUPLICATE HEADER ID: #{anchor}, please consider rewording" if ENV.key?("WARN_DUPLICATE_HEADERS")
        else
          anchors << anchor
        end
      end

      # Also, footnotes are rendered as paragraphs this way.
      anchors += Set.new(html.scan(/<p\s+class="footnote"\s+id="([^"]+)/).flatten)
      return anchors
    end
    
    def check_fragment_identifiers(html, anchors)
      html.scan(/<a\s+href="#([^"]+)/).flatten.each do |fragment_identifier|
        next if fragment_identifier == 'mainCol' # in layout, jumps to some DIV
        unless anchors.member?(fragment_identifier)
          guess = anchors.min { |a, b|
            Levenshtein.distance(fragment_identifier, a) <=> Levenshtein.distance(fragment_identifier, b)
          }
          puts "*** BROKEN LINK: ##{fragment_identifier}, perhaps you meant ##{guess}."
        end
      end
    end

    def settings_content
      @settings_content ||=
        begin
          settings_filename = File.join(view_path, 'settings.txt')
          if File.exist?(settings_filename)
            File.read(settings_filename)
          else
            ''
          end
        end
    end
    
  end
end
