require 'nokogiri'
require 'optparse'
require 'time'
require 'pathname'

# ハバースインの公式で2地点間の距離を計算
def haversine_distance(lat1, lon1, lat2, lon2)
  radius = 6371.0 # 地球の半径 (km)
  dlat = to_radians(lat2 - lat1)
  dlon = to_radians(lon2 - lon1)
  a = Math.sin(dlat / 2)**2 + Math.cos(to_radians(lat1)) * Math.cos(to_radians(lat2)) * Math.sin(dlon / 2)**2
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  radius * c * 1000 # 距離をメートルに変換して返す
end

def to_radians(degrees)
  degrees * Math::PI / 180.0
end

# コマンドラインオプションの解析
year = nil
OptionParser.new do |opts|
  opts.banner = "Usage: ruby health_data_summary.rb [options]"

  opts.on("-y", "--year YEAR", "Specify the year to filter records") do |y|
    year = y.to_i
  end
end.parse!

if year.nil?
  puts "Error: Please specify a year using the -y or --year option."
  exit 1
end

# ディレクトリ設定
dir_path = 'workout-routes'

unless Dir.exist?(dir_path)
  puts "Error: Directory '#{dir_path}' does not exist."
  exit 1
end

puts "Processing GPX files for the year: #{year}..."

# 集計用変数
workout_days = 0
total_distance = 0.0
total_time_seconds = 0

# 名前空間の定義
namespaces = { 'gpx' => 'http://www.topografix.com/GPX/1/1' }

# ファイルを走査
Dir.glob(File.join(dir_path, "route_*.gpx")) do |file_path|
  file_name = File.basename(file_path)
  match = file_name.match(/route_(\d{4})-(\d{2})-(\d{2})_\d{1,2}\.\d{2}(am|pm)\.gpx$/)

  puts "Checking file: #{file_name} (Matched year: #{match ? match[1] : 'No match'})"
  next unless match && match[1].to_i == year

  # ファイルの日付を運動日としてカウント
  workout_days += 1

  # GPXファイルを解析して移動距離を計算
  file = File.open(file_path)
  doc = Nokogiri::XML(file)
  file.close

  # トラックポイントの解析
  previous_point = nil
  previous_time = nil
  doc.xpath('//gpx:trkpt', namespaces).each do |trkpt|
    lat = trkpt['lat'].to_f
    lon = trkpt['lon'].to_f
    time = trkpt.at_xpath('gpx:time', namespaces)&.content
    time_obj = Time.parse(time) if time

    if previous_point && previous_time
      distance_m = haversine_distance(previous_point[:lat], previous_point[:lon], lat, lon)
      total_distance += distance_m / 1000.0 # 累計距離は km 単位で保持
      elapsed_time = (time_obj - previous_time).to_i
      total_time_seconds += elapsed_time
    end

    previous_point = { lat: lat, lon: lon }
    previous_time = time_obj
  end
end

# 結果を出力
if total_distance.zero?
  puts "Warning: No distances calculated. Check if GPX files contain <trkpt> elements and valid coordinates."
end

total_time_hours = total_time_seconds / 3600.0

puts "\nResults for the year #{year}:"
puts "運動日数: #{workout_days}"
puts "年間累計移動距離: #{total_distance.round(2)} km"
puts "年間累計運動時間: #{total_time_hours.round(2)} hours"

