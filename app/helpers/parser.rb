require_relative 'parser_base'
require 'nokogiri'
require 'time'

class KassaParser
  extend ParserBase

  HAS_SUBS = 'языке оригинала'.freeze
  NOT_FOUND_SCREENING = /Сеанс не найден/
  TITLE_DELIMITER = ' на языке оригинала'.freeze

  def self.parse_prices(data)
    parsed = parse_json(data)

    fee = 1.1 # Kassa's fee is 10% (if applied)
    min_price = 10**9 # inf for poor people
    max_price = 0

    begin
      parsed['OrderZones'].each do |order_zone|
        order_zone['Orders'].each do |order|
          price = order['Price']
          price = (price / fee).round(0) if order['HasFee']
          max_price = price if price > max_price
          min_price = price if price < min_price
        end
      end
      max_price, min_price = max_price.to_i, min_price.to_i
      max_price, min_price = nil, nil if max_price.zero?
      [max_price, min_price]
    rescue
      [nil, nil]
    end
  end

  def self.parse_prices_full(data)
    data = '<!DOCTYPE html><html>' + data + '</html>'
    doc = Nokogiri::XML.parse(data)
    prices = (doc / 'div.b-cinema-plan/div[@data]').map { |el| el[:data].split('|')[3].to_i rescue nil }
    prices = prices.select(&:positive?).compact.uniq.sort # occupied places have 0 price, remove before proc.
    [prices.last, prices.first]
  rescue
    [nil, nil]
  end

  def self.parse_sessions_html(data, date, cinema_id = 0, movie_id = 0)
    doc = Nokogiri::XML.parse(data)
    results = []
    begin
      (doc / '.heading').each do |el|
        # looking up and aside in the DOM to find the cinema info
        session_cinema_id = get_cinema_id(el.at('a')[:href])
        session_cinema_id = cinema_id.to_i if session_cinema_id.to_i.zero?
        session_cinema = Cinema.where(cinema_id: session_cinema_id).first

        fetch_all = false
        fetch_all = session_cinema.fetch_all unless session_cinema.nil?

        fetch_mode_movie = Movie.get_movie(movie_id).fetch_mode rescue FETCH_MODE[:movie][:subs]
        fetch_all = true if fetch_mode_movie == FETCH_MODE[:movie][:all]

        next if (!el.parent.parent.search('.caption').inner_text.include? HAS_SUBS) && !fetch_all
        # skip headlines of non-subs sessions
        # but download all screenings for given cinemas
        if fetch_all
          links = el.parent.parent.search('.sked a.sked_item') rescue []
        else
          el.parent.parent.search('.caption').each do |s|
            links = s.parent.search('a.sked_item') if s.inner_text.include? HAS_SUBS rescue []
          end
        end

        # looking up and then down to find the sessions info
        links.each do |a|
          session_id = get_session_id(a[:href])
          session_time = parse_time(a.inner_html, date)
          # the night screenings are technically on the next day!
          session_time += 1.day if session_time.hour.between? 0, 5
          session_movie = get_movie_id(el.at('a')[:href]) rescue nil
          results << { session: session_id, time: session_time, cinema: session_cinema_id, movie: session_movie }
        end
      end
    end
    results
  end

  def self.parse_movie_genres(doc)
    genres = (doc / 'h3.item_title3').first.inner_text.strip.lines[0].strip.chomp(',') rescue nil
    genres = genres.mb_chars.downcase.to_s.strip unless genres.nil?
    genres.to_s.empty? ? nil : genres
  end

  def self.parse_movie_title(doc)
    (doc / 'h1.item_title').first.inner_text.strip rescue nil
  end

  def self.parse_movie_title_original(doc)
    (doc / 'h2.item_title2').first.inner_text.split('—')[0].strip rescue nil
  end

  def self.parse_movie_age_restriction(doc)
    (doc / 'h3.item_title3').first.inner_text.strip.lines[-1].strip.to_i rescue nil
  end

  def self.parse_movie_year(doc)
    year = (doc / 'h2.item_title2').first.inner_text.strip.lines[-1].to_i rescue nil
    year.to_i.zero? || year.to_i < 1900 ? nil : year
  end

  def self.parse_movie_poster(doc)
    poster = (doc / 'div.item_img > img').first[:src] rescue nil
    poster =~ /empty/ ? nil : poster
  end

  def self.parse_movie_duration(doc)
    duration = doc.css('span.dd')[0].inner_text.split(' ')[0].to_i rescue nil
    duration.to_i > 1900 ? nil : duration
  end

  def self.parse_movie_country(doc)
    country = doc.css('span.dd')[1].inner_text.strip rescue nil
    country.to_s.strip == '-' ? nil : country
  end

  def self.parse_movie_director(doc)
    doc.css('span.dd[itemprop=name]').first.inner_text.strip rescue nil
  end

  def self.parse_movie_actors(doc)
    (doc / 'span.item_peop__actors').first.inner_text.strip rescue nil
  end

  def self.parse_movie_description(doc)
    (doc / 'span.item_desc__text-full').first.inner_text.strip rescue nil
  end

  def self.parse_movie_html(data)
    doc = Nokogiri::XML.parse(data) rescue nil
    return nil if doc.nil?

    title = parse_movie_title(doc)
    return nil if title.nil?

    {
      actors: parse_movie_actors(doc),
      age_restriction: parse_movie_age_restriction(doc),
      country: parse_movie_country(doc),
      description: parse_movie_description(doc),
      director: parse_movie_director(doc),
      duration: parse_movie_duration(doc),
      genres: parse_movie_genres(doc),
      poster: parse_movie_poster(doc),
      title: title,
      title_original: parse_movie_title_original(doc),
      year: parse_movie_year(doc)
    }
  end

  def self.parse_tickets_available?(data)
    parsed = parse_json(data) rescue nil
    if parsed.nil?
      false
    else
      !(parsed['error'] == true || parsed['maxPlaceCount'].zero?)
    end
  end

  def self.parse_movie_dates(data)
    # https://m.kassa.rambler.ru/spb/movie/59237?date=2016.03.28&WidgetID=16857&geoPlaceID=3
    doc = Nokogiri::XML.parse(data)
    (doc / 'option').map { |o| Time.parse(get_first_regex_match(o[:value], /date=([\d\.]+)/)) rescue Time.now.strip }
  end

  def self.get_session_id(link)
    # https://w.kassa.rambler.ru/event/33040795/340fc69e-10f4-423e-a19c-1a5fd3ca94b6/http%3a%2f%2fm.kassa.rambler.ru%2fmsk%2fmovie%2f66499/
    # => 33040795
    get_first_regex_match_integer(link, %r{event\/(\d+)})
  end

  def self.get_movie_id(link)
    # https://m.kassa.rambler.ru/msk/movie/51945?geoplaceid=2&widgetid=16857
    # => 51945
    get_first_regex_match_integer(link, %r{movie\/(\d+)})
  end

  def self.get_cinema_id(link)
    # https://m.kassa.rambler.ru/msk/cinema/kinoklub-fitil-2729?WidgetID=16857&geoPlaceID=2
    # => 2729
    get_first_regex_match_integer(link, %r{cinema\/.*\-(\d+)})
  end

  def self.parse_time(time, date)
    # 11:10 => given date at 11:10
    # for a different time zone: Time.parse(date.strftime("%Y-%m-%d") + " " + time + " +0400")
    Time.parse(date.strftime('%Y-%m-%d') + ' ' + time)
  end

  def self.screening_exists?(data)
    doc = Nokogiri::XML.parse(data) rescue nil
    return false if doc.nil?
    ((doc.at('title').inner_text rescue nil) =~ NOT_FOUND_SCREENING).nil?
  end

  def self.screening_has_subs?(data, skip_unavailable = true)
    doc = Nokogiri::XML.parse(data) rescue nil
    return false if doc.nil?
    title = doc.at('title').inner_text rescue ''
    (title.include? HAS_SUBS) || skip_unavailable
  end

  def self.screening_title(data)
    doc = Nokogiri::XML.parse(data) rescue nil
    return '' if doc.nil?
    title = doc.at('title').inner_text rescue ''
    title.split(TITLE_DELIMITER).first
  end

  def self.screening_date_time(data)
    overnight = 'в ночь с'
    months = %w[янв фев мар апр май июн июл авг сен окт ноя дек]
    doc = Nokogiri::XML.parse(data) rescue nil
    return nil if doc.nil?
    date_text = doc.at('.order-info dd:nth-of-type(3)').inner_text rescue ''
    tokens = date_text.split ' '
    day = tokens[1]
    month_name = tokens[2]
    month = Time.now.month
    months.each_with_index do |m, i|
      next unless month_name.include? m rescue nil
      month = i + 1
    end
    time = tokens[4]
    year = Time.now.year
    year += 1 if Time.now.month > month
    date = Time.local(year, month, day, 0, 0, 0)
    date += 1.day if date_text.include? overnight
    parse_time(time, date)
  end

  private_class_method	:parse_time
  private_class_method	:get_cinema_id
  private_class_method	:get_session_id

  public_class_method		:parse_prices
  public_class_method		:parse_sessions_html
  public_class_method		:screening_exists?
  public_class_method		:parse_tickets_available?
  public_class_method		:parse_movie_dates
end
