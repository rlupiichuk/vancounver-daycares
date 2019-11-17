require 'faraday'
require 'lightly'
require 'csv'
require 'geocoder'

$cache = Lightly.new dir: './childcare_cache', life: '365d'

class Lightly
  def [](key)
    load(key) if cached?(key)
  end

  def []=(key, value)
    save(key, value)
  end

  def del(key)
    clear(key)
  end
end

Geocoder.configure(
  timeout: 5,
  units: :km,
  cache: $cache
)

def get(url)
  $cache.get url do
    Faraday.get(url).body
  end
end

index_body = get 'https://www.healthspace.ca/Clients/FHA/FHA_Website.nsf/CCFL-Child-List-All?OpenView&RestrictToCategory=23B11DF8A3C9C1E63649D5E3AD0748DC&count=1000&start=1'
index_pattern = /<img src="\/Clients\/FHA\/FHA_Website\.nsf\/linksquare\.gif" alt=""><a href="([^"]+)">([^<]+)<\/A><\/td><td valign="top" NOWRAP>&nbsp;([^<]+)<\/td>/
daycares = index_body.scan index_pattern

location_pattern = /<B>Facility Location:<\/B><BR>([^<]+)<\/P>/
type_pattern = /<tr><td><b>Facility Information:<\/b><\/td><\/tr>\s*<tr><td>Facility Type: (.+)<\/td><\/tr>\s*<tr><td>Service Type\(s\): (.+)<\/td>\s*<\/tr>\s*<tr><td>Capacity: (\d+)<\/td><\/tr>/
inspection_pattern = />Routine Inspection<\/a>/

central_park_coordinates = [49.2276595, -123.0179715]

daycares = daycares.map do |url, name, phone|
  url = "https://www.healthspace.ca#{url}"
  daycare_body = get url
  location = daycare_body.match(location_pattern)[1].strip
  _, facility_type, service_type, capacity = daycare_body.match(type_pattern).to_a.map(&:strip)
  num_inspections = daycare_body.scan(inspection_pattern).length

  next if service_type == '304 Family Child Care'
  next if service_type == '311 In-Home Multi-Age Child Care'
  next if service_type == '310 Multi-Age Child Care'
  next if service_type == '305 Group Child Care (School Age)'
  next if capacity.to_i <= 10

  sanitized_location = location.gsub(/,\s*.{3}\s*.{3}$/, '')
                               .gsub(/^.{1,10}\s*\-\s*/, '')
  encoded_location = Geocoder.search(sanitized_location)[0]

  print '.'

  {
    name: name,
    phone: phone,
    location: location,
    service_type: service_type,
    capacity: capacity,
    num_inspections: num_inspections,
    coordinates: encoded_location&.coordinates,
    distance_to_central_park: Geocoder::Calculations.distance_between(central_park_coordinates, encoded_location&.coordinates).round(2),
  }
end

puts "\nFINISHED"

daycares = daycares.compact.sort_by { |daycare| daycare[:distance_to_central_park] }

CSV.open('./childcares.csv', 'w') do |csv|
  csv << [
    'name',
    'phone',
    'location',
    'service_type',
    'capacity',
    'num_inspections',
    'distance_to_central_park',
    'coordinates',
  ]
  daycares.each do |daycare|
    csv << [
      daycare[:name],
      daycare[:phone],
      daycare[:location],
      daycare[:service_type],
      daycare[:capacity],
      daycare[:num_inspections],
      daycare[:distance_to_central_park],
      (daycare[:coordinates] || []).map(&:to_s).join(', ')
    ]
  end
end