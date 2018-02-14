require 'active_support/all'
require 'sinatra/base'
require 'pry'
require 'icalendar'
require 'faraday'

Time.zone = 'America/Chicago'

class VacancyDetector
  def initialize(calendar_url)
    @calendar_url = calendar_url
  end

  def vacancies
    response = Faraday.get(@calendar_url)
    cal = Icalendar::Calendar.parse(response.body).first
    events = todays_events(cal)
    state_changes = collect_timestamps(events)
    detect_vacancies(state_changes)
  end

  protected

  def today?(dt)
    start_of_day = DateTime.now.beginning_of_day.utc
    end_of_day = DateTime.now.end_of_day.utc

    dt >= start_of_day && dt <= end_of_day
  end

  def todays_events(cal)
    ret = []
    cal.events.each do |e|
      next if e.dtend.nil? || e.dtstart.nil?
      # ret << e if e.dtstart.in_time_zone.to_date == Date.today || e.dtend.in_time_zone.to_date == Date.today
      ret << e if today?(e.dtstart) || today?(e.dtend)
    end
    ret
  end

  def collect_timestamps(events)
    state_changes = []
    events.each do |e|
      state_changes << OpenStruct.new(tstamp: e.dtstart.utc, type: :claimed)
      state_changes << OpenStruct.new(tstamp: e.dtend.utc, type: :freed)
    end
    state_changes.sort_by{ |x| x.tstamp }
  end

  def detect_vacancies(state_changes)
    vacancies = []
    tmp = nil

    if state_changes.first.type == :claimed
      state_changes.unshift(OpenStruct.new(tstamp: DateTime.now.beginning_of_day.utc, type: :freed))
    end

    state_changes.each do |c|
      if c.type == :freed
        tmp = { start_time: c.tstamp.utc, end_time: nil }
      else
        binding.pry unless c.type == :claimed
        tmp[:end_time] = c.tstamp.utc unless tmp.nil?
        vacancies << tmp
        tmp = nil
      end
    end

    unless tmp.nil?
      tmp[:end_time] = DateTime.now.end_of_day.utc
      vacancies << tmp
    end
    vacancies
  end
end


class MyApp < Sinatra::Base
  before do
    content_type 'application/json'
  end
  get '/' do
    detector = VacancyDetector.new('https://calendar.google.com/calendar/ical/tcmaker.org_2d3935333934333630383333%40resource.calendar.google.com/public/basic.ics')
    vacancies = detector.vacancies
    JSON.generate(vacancies)
  end
end

MyApp.run!
