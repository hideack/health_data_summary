require 'nokogiri'
require 'optparse'
require 'time'
require 'date'

# ハバースインの公式で2地点間の距離を計算
def haversine_distance(lat1, lon1, lat2, lon2)
  radius = 6371.0 # 地球の半径 (km)
  dlat = to_radians(lat2 - lat1)
  dlon = to_radians(lon2 - lon1)

  a = Math.sin(dlat / 2)**2 +
      Math.cos(to_radians(lat1)) * Math.cos(to_radians(lat2)) *
      Math.sin(dlon / 2)**2

  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  radius * c * 1000 # meters
end

def to_radians(degrees)
  degrees * Math::PI / 180.0
end

def seconds_to_hms(total_seconds)
  total_seconds = total_seconds.to_i
  h = total_seconds / 3600
  m = (total_seconds % 3600) / 60
  s = total_seconds % 60
  format("%02d:%02d:%02d", h, m, s)
end

def pace_min_per_km(total_seconds, total_km)
  return nil if total_km <= 0
  sec_per_km = total_seconds.to_f / total_km
  min = (sec_per_km / 60).floor
  sec = (sec_per_km % 60).round
  # 丸めで 60 秒になるケースの補正
  if sec == 60
    min += 1
    sec = 0
  end
  format("%d:%02d /km", min, sec)
end

# コマンドラインオプションの解析
year = nil
OptionParser.new do |opts|
  opts.banner = "Usage: ruby health_data_summary.rb [options]"
  opts.on("-y", "--year YEAR", "Specify the year to filter records") { |y| year = y.to_i }
end.parse!

if year.nil?
  warn "Error: Please specify a year using the -y or --year option."
  exit 1
end

# ディレクトリ設定
dir_path = 'workout-routes'
unless Dir.exist?(dir_path)
  warn "Error: Directory '#{dir_path}' does not exist."
  exit 1
end

# 名前空間の定義
namespaces = { 'gpx' => 'http://www.topografix.com/GPX/1/1' }

# 集計用（全体）
workout_days = 0
total_distance_km = 0.0
total_time_seconds = 0

# 追加集計のための配列（ファイル＝1ワークアウト単位）
workouts = [] # { date: Date, distance_km: Float, time_seconds: Integer }

# 月別・曜日別
monthly = Hash.new { |h, k| h[k] = { count: 0, distance_km: 0.0, time_seconds: 0 } } # k: "YYYY-MM"
weekday = Hash.new { |h, k| h[k] = { count: 0, distance_km: 0.0, time_seconds: 0 } } # k: 0..6

# ファイルを走査
pattern = File.join(dir_path, "route_*.gpx")
files = Dir.glob(pattern)

if files.empty?
  warn "Warning: No GPX files found in '#{dir_path}' (pattern: #{pattern})"
end

files.each do |file_path|
  file_name = File.basename(file_path)
  match = file_name.match(/route_(\d{4})-(\d{2})-(\d{2})_\d{1,2}\.\d{2}(am|pm)\.gpx$/)
  next unless match
  next unless match[1].to_i == year

  date = Date.new(match[1].to_i, match[2].to_i, match[3].to_i)

  # GPXファイルを解析して移動距離・時間を計算（このファイル単位）
  doc = Nokogiri::XML(File.read(file_path))

  file_distance_km = 0.0
  file_time_seconds = 0

  previous_point = nil
  previous_time = nil

  doc.xpath('//gpx:trkpt', namespaces).each do |trkpt|
    lat = trkpt['lat'].to_f
    lon = trkpt['lon'].to_f
    time_str = trkpt.at_xpath('gpx:time', namespaces)&.content
    time_obj = Time.parse(time_str) if time_str

    if previous_point && previous_time && time_obj
      distance_m = haversine_distance(previous_point[:lat], previous_point[:lon], lat, lon)
      elapsed = (time_obj - previous_time).to_i

      # 逆行・異常値対策（たまに時刻が欠けたり逆順だったりする）
      if elapsed > 0
        file_distance_km += (distance_m / 1000.0)
        file_time_seconds += elapsed
      end
    end

    previous_point = { lat: lat, lon: lon }
    previous_time = time_obj
  end

  # 「運動日数」は、該当年のファイルを1つでも処理したら+1
  workout_days += 1
  total_distance_km += file_distance_km
  total_time_seconds += file_time_seconds

  workouts << { date: date, distance_km: file_distance_km, time_seconds: file_time_seconds }

  month_key = format("%04d-%02d", date.year, date.month)
  monthly[month_key][:count] += 1
  monthly[month_key][:distance_km] += file_distance_km
  monthly[month_key][:time_seconds] += file_time_seconds

  wday = date.wday # 0:Sun..6:Sat
  weekday[wday][:count] += 1
  weekday[wday][:distance_km] += file_distance_km
  weekday[wday][:time_seconds] += file_time_seconds
end

if workout_days == 0
  puts "No workouts found for year #{year}. Check file names and directory '#{dir_path}'."
  exit 0
end

# (1) 平均
avg_distance_km = total_distance_km / workout_days
avg_time_seconds = total_time_seconds.to_f / workout_days
avg_pace = pace_min_per_km(total_time_seconds, total_distance_km)

# (2) 最長
longest_distance = workouts.max_by { |w| w[:distance_km] }
longest_time = workouts.max_by { |w| w[:time_seconds] }

# (4) 週あたり平均（ISO週：Date.new(year,12,28).cweek でその年の週数が取れる）
weeks_in_year = Date.new(year, 12, 28).cweek
avg_workouts_per_week = workout_days.to_f / weeks_in_year

# 出力
puts "\nResults for the year #{year}:"
puts "運動日数: #{workout_days}"
puts "年間累計移動距離: #{total_distance_km.round(2)} km"
puts "年間累計運動時間: #{(total_time_seconds / 3600.0).round(2)} hours (#{seconds_to_hms(total_time_seconds)})"

puts "\n(1) 1回あたり平均:"
puts "  平均距離: #{avg_distance_km.round(2)} km / 回"
puts "  平均時間: #{(avg_time_seconds / 3600.0).round(2)} hours / 回 (#{seconds_to_hms(avg_time_seconds)})"
puts "  平均ペース: #{avg_pace || 'N/A'}"

puts "\n(2) 最長記録:"
puts "  最長距離: #{longest_distance[:distance_km].round(2)} km (#{longest_distance[:date]})"
puts "  最長時間: #{(longest_time[:time_seconds] / 3600.0).round(2)} hours (#{seconds_to_hms(longest_time[:time_seconds])}) (#{longest_time[:date]})"

puts "\n(3) 月別サマリ:"
puts "  月      回数   距離(km)   時間(h)   平均ペース"
monthly.keys.sort.each do |m|
  c = monthly[m][:count]
  d = monthly[m][:distance_km]
  t = monthly[m][:time_seconds]
  p = pace_min_per_km(t, d) || 'N/A'
  puts format("  %-7s %4d %10.2f %8.2f   %s", m, c, d, (t / 3600.0), p)
end

puts "\n(4) 曜日別サマリ:"
weekday_names = ["日", "月", "火", "水", "木", "金", "土"]
puts "  曜日   回数   距離(km)   時間(h)"
(0..6).each do |w|
  c = weekday[w][:count]
  d = weekday[w][:distance_km]
  t = weekday[w][:time_seconds]
  puts format("  %-2s %6d %10.2f %8.2f", weekday_names[w], c, d, (t / 3600.0))
end
puts "\n  週あたり平均回数: #{avg_workouts_per_week.round(2)} 回/週 (ISO週: #{weeks_in_year}週換算)"

