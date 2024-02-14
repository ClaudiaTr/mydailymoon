require "json"
require "open-uri"
require "net/http"
require "nokogiri"

class CalendarController < ApplicationController
  def day
    params[:date] ||= Date.today
    fetch_moon_data_today if Moon.where(date: params[:date], location: current_user.location.delete(' ')) == []
    display_moon_data
    daily_horoscope
  end

  def month
    params[:date] ||= Date.today
    params[:start_date] ||= params[:date]
    fetch_moon_data_month if Moon.where(date: (params[:start_date].to_date.beginning_of_month..params[:start_date].to_date.end_of_month), location: current_user.location.delete(' ')).count < params[:start_date].to_date.end_of_month.day
  end

  private

  def fetch_moon_data_today
    start_date = params[:date].to_date - 3
    end_date = params[:date].to_date + 2
    api_call(start_date, end_date)
  end

  def fetch_moon_data_month
    start_date = params[:start_date].to_date.beginning_of_month
    end_date = params[:start_date].to_date.end_of_month
    api_call(start_date, end_date)
  end

  def api_call(start_date, end_date)
    # url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/#{current_user.location.delete(' ')}/#{start_date}/#{end_date}?key=ENV['VISUALCROSSING_KEY']&include=days&elements=datetime,moonphase,sunrise,sunset,moonrise,moonset"
    url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/#{current_user.location.delete(' ')}/#{start_date}/#{end_date}?key=FTZ5BKMXATN4FZ3RAF5PS5RN5&include=days&elements=datetime,moonphase,sunrise,sunset,moonrise,moonset"
    data_serialized = URI.open(url,
      "User-Agent" => "").read
    data = JSON.parse(data_serialized)
    moon_data = data["days"]
    @timezone = data["timezone"]

    moon_data.each do |md|
      define_moon_phase(md)
      md["moonrise"] == nil ? moonrise = "No moonrise" : moonrise = md["datetime"] + " " + md["moonrise"]
      md["moonset"] == nil ? moonset = "No moonset" : moonset = md["datetime"] + " " + md["moonset"]
      Moon.create(phase: md["moonphase"], moon_phase_name: @moon_phase_name, moon_phase_img: @moon_phase_img, date: md["datetime"], moonrise: moonrise, moonset: moonset, location: data["address"], display_location: data["resolvedAddress"], moon_sign: fetch_moon_sign(md["datetime"]))
    end
  end

  def define_moon_phase(day_data)
    moon_phase = day_data["moonphase"]
    if moon_phase == 0 || moon_phase == 1
      @moon_phase_name = "New Moon"; @moon_phase_img = "moon1new.png"
    elsif moon_phase < 0.25
      @moon_phase_name = "Waxing Crescent"; @moon_phase_img = "moon2waxingcrescent.png"
    elsif moon_phase == 0.25
      @moon_phase_name = "First Quarter"; @moon_phase_img = "moon3firstquarter.png"
    elsif moon_phase < 0.5
      @moon_phase_name = "Waxing Gibbous"; @moon_phase_img = "moon4waxinggibbous.png"
    elsif moon_phase == 0.5
      @moon_phase_name = "Full Moon"; @moon_phase_img = "moon5full.png"
    elsif moon_phase < 0.75
      @moon_phase_name = "Waning Gibbous"; @moon_phase_img = "moon6waninggibbous.png"
    elsif moon_phase == 0.75
      @moon_phase_name = "Last Quarter"; @moon_phase_img = "moon7lastquarter.png"
    else moon_phase < 1
      @moon_phase_name = "Waning Crescent"; @moon_phase_img = "moon8waningcrescent.png"
    end
  end

  def fetch_moon_sign(day)
    date_day = day.to_date.day
    date_month = day.to_date.month
    date_year = day.to_date.year
    url = "https://www.lunarium.co.uk/calculators/moonsign/?birthDay=#{date_day}&birthMonth=#{date_month}&birthYear=#{date_year}&birthHour=12&birthMinute=0&timeNotKnown=true&timeZone=#{@timezone}"
    html = URI.open(url)
    doc = Nokogiri::HTML(html)
    doc.search(".container h2")[0].text.strip.split(" ")[-1]
  end

  def display_moon_data
    moon_today = Moon.where(date: params[:date], location: current_user.location.delete(' ')).first
    @moonimage = moon_today.moon_phase_img
    if moon_today.moonrise
      @moonrise = moon_today.moonrise.strftime("%H:%M")
    else
      @moonrise = "N/A"
    end
    if moon_today.moonset
      @moonset = moon_today.moonset.strftime("%H:%M")
    else
      @moonset = "N/A"
    end
    @moonphase = moon_today.moon_phase_name
    @moonsign = moon_today.moon_sign
    @moon_emoji = zodiac_emoji(@moonsign.downcase)
    @moonlocation = moon_today.display_location
  end

  def daily_horoscope
    moon_today = Moon.where(date: params[:date], location: current_user.location.delete(' ')).first
    if moon_today.date == Date.today
      fetch_daily_horoscope("today")
    elsif moon_today.date == Date.today - 1
      fetch_daily_horoscope("yesterday")
    elsif moon_today.date == Date.today + 1
      fetch_daily_horoscope("tomorrow")
    elsif moon_today.date < Date.today
      @daily_horoscope = "✨ Let the past be the past. This day has come and gone. What has been is what had to be. What has not been, was never meant to be. ✨"
    elsif moon_today.date > Date.today
      @daily_horoscope = "✨ Don't get too caught up in the future. The time is now and it's advisable to live in the present moment. Come back on #{(moon_today.date - 1.day).strftime("%B %d")} at the earliest to see your horoscope for this day. ✨"
    end
  end

  def fetch_daily_horoscope(day)
    signs = {
      "aries" => 1,
      "taurus" => 2,
      "gemini" => 3,
      "cancer" => 4,
      "leo" => 5,
      "virgo" => 6,
      "libra" => 7,
      "scorpio" => 8,
      "sagittarius" => 9,
      "capricorn" => 10,
      "aquarius" => 11,
      "pisces" => 12,
    }

    url = "https://www.horoscope.com/us/horoscopes/general/horoscope-general-daily-#{day}.aspx?sign=#{signs[current_user.zodiac_sign.downcase]}"
    html_file = URI.open(url).read
    html_doc = Nokogiri::HTML.parse(html_file)
    @daily_horoscope = html_doc.css(".main-horoscope p").first.text.match(/.-.(.*)\./).to_s.delete_prefix(" - ")
  end
end
