require "feedjira"
require "httparty"
require "jekyll"
require "nokogiri"
require "time"

# Ensure Feedjira has parsers loaded
require "feedjira/parser/rss"
require "feedjira/parser/atom"

module ExternalPosts
  class ExternalPostsGenerator < Jekyll::Generator
    safe true
    priority :high

    def generate(site)
      sources = site.config["external_sources"]
      return if sources.nil?

      sources.each do |src|
        Jekyll.logger.info "ExternalPosts:", "Fetching external posts from #{src['name']}"

        if src["rss_url"]
          fetch_from_rss(site, src)
        elsif src["posts"]
          fetch_from_urls(site, src)
        end
      end
    end

    # ---------------------------
    # SAFE RSS FETCHING
    # ---------------------------
    def fetch_from_rss(site, src)
      begin
        xml = HTTParty.get(src["rss_url"], timeout: 10).body
        if xml.nil? || xml.strip.empty?
          Jekyll.logger.warn "ExternalPosts:", "Empty RSS response from #{src['rss_url']}"
          return
        end

        feed = Feedjira.parse(xml)

        unless feed.respond_to?(:entries)
          Jekyll.logger.warn "ExternalPosts:", "No valid RSS parser for #{src['rss_url']}"
          return
        end

        process_entries(site, src, feed.entries)

      rescue StandardError => e
        Jekyll.logger.warn "ExternalPosts:", "Failed to parse RSS for #{src['name']} (#{src['rss_url']}): #{e.class} – #{e.message}"
      end
    end

    # ---------------------------
    # PROCESS FEED ENTRIES
    # ---------------------------
    def process_entries(site, src, entries)
      return if entries.nil?

      entries.each do |e|
        Jekyll.logger.info "ExternalPosts:", "Fetching #{e.url}"

        create_document(site, src["name"], e.url, {
          title:     safe(e.title),
          content:   safe(e.content),
          summary:   safe(e.summary),
          published: e.published || Time.now
        })
      end
    end

    # ---------------------------
    # CREATE DOCUMENT
    # ---------------------------
    def create_document(site, source_name, url, content)
      title_sanitized = content[:title].to_s.gsub(/[^\w]/, "").strip

      if title_sanitized.empty?
        slug = "#{source_name.downcase.gsub(' ', '-').gsub(/[^\w-]/, '')}-#{url.split('/').last}"
      else
        slug = content[:title]
               .downcase
               .strip
               .gsub(" ", "-")
               .gsub(/[^\w-]/, "")
        slug = "#{source_name.downcase.gsub(' ', '-').gsub(/[^\w-]/, '')}-#{url.split('/').last}" if slug.empty?
      end

      path = site.in_source_dir("_posts/#{slug}.md")

      doc = Jekyll::Document.new(
        path, { site: site, collection: site.collections["posts"] }
      )

      doc.data["external_source"] = source_name
      doc.data["title"]          = content[:title]
      doc.data["feed_content"]   = content[:content]
      doc.data["description"]    = content[:summary]
      doc.data["date"]           = content[:published]
      doc.data["redirect"]       = url
      doc.content                = content[:content]

      site.collections["posts"].docs << doc
    end

    # ---------------------------
    # FETCH STATIC HTML POSTS
    # ---------------------------
    def fetch_from_urls(site, src)
      src["posts"].each do |post|
        Jekyll.logger.info "ExternalPosts:", "Fetching #{post['url']}"

        begin
          content = fetch_content_from_url(post["url"])
          content[:published] = parse_published_date(post["published_date"])
          create_document(site, src["name"], post["url"], content)

        rescue StandardError => e
          Jekyll.logger.warn "ExternalPosts:", "Error fetching #{post['url']}: #{e.message}"
        end
      end
    end

    def parse_published_date(published_date)
      case published_date
      when String
        Time.parse(published_date).utc
      when Date
        published_date.to_time.utc
      when Time
        published_date.utc
      else
        Jekyll.logger.warn "ExternalPosts:", "Invalid date format: #{published_date.inspect}"
        Time.now.utc
      end
    end

    # ---------------------------
    # FETCH + PARSE HTML
    # ---------------------------
    def fetch_content_from_url(url)
      html = HTTParty.get(url, timeout: 10).body
      parsed_html = Nokogiri::HTML(html)

      title = parsed_html.at("head title")&.text.to_s.strip
      description =
        parsed_html.at('head meta[name="description"]')&.attr("content") ||
        parsed_html.at('head meta[name="og:description"]')&.attr("content") ||
        parsed_html.at('head meta[property="og:description"]')&.attr("content")

      body_content = parsed_html.search("p").map { |e| e.text }.join("\n")

      {
        title:   title,
        content: body_content,
        summary: description
      }
    end

    # ---------------------------
    # UTILITY
    # ---------------------------
    def safe(value)
      value.to_s
    end
  end
end
