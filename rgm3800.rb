#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloader for the RoyalTek RGM-3800 GPS logger. See README.md and docs/protocol.md.

require 'date'
require 'io/wait'
require 'optparse'

module RGM3800
  class Error < StandardError; end

  RECORD_LEN = { 0 => 12, 1 => 16, 2 => 20, 3 => 24, 4 => 60 }.freeze
  FORMAT_DESC = { 0 => 'time, lat, lon', 1 => 'time, lat, lon, alt', 2 => 'time, lat, lon, alt, vel' }.freeze
  MEMORY_FULL = { 0 => 'overwrite', 1 => 'stop' }.freeze
  ROLLOVER = 7168 # days (1024 weeks): the logger's dates are this much too early since 2026

  Waypoint = Struct.new(:h, :m, :s, :lat, :lon, :alt, :vel)

  module_function

  # --- Record decoding and NMEA conversion ---

  def check_format(format)
    raise Error, "record format #{format} is not supported (only 0-2)" unless FORMAT_DESC.key?(format)
  end

  # Returns a Waypoint, or nil if the record's valid byte is not 1.
  def decode(record, format)
    check_format(format)
    valid, h, m, s, lat, lon, alt, vel = record.unpack('C4e4')
    return nil unless valid == 1

    Waypoint.new(h, m, s, lat, lon, format >= 1 ? alt : 0.0, format >= 2 ? vel : 0.0)
  end

  def f32(x) = [x].pack('e').unpack1('e')

  RAD2DEG = f32(180 / Math::PI)

  # Single-precision degrees, double-precision minutes, as the official tool does.
  def coord(rad, width)
    deg = f32(rad.abs * RAD2DEG)
    format("%0#{width}d%07.4f", deg.floor, (deg - deg.floor) * 60.0)
  end

  def nmea_line(body)
    format("$%s*%02X\r\n", body, body.bytes.reduce(0, :^))
  end

  # Converts the waypoints of one track to official-style NMEA text.
  def nmea(waypoints, start_date)
    date = start_date
    prev = nil
    waypoints.map do |w|
      tod = [w.h, w.m, w.s]
      date += 1 if prev && (tod <=> prev).negative?
      prev = tod
      time = format('%02d%02d%02d.000', *tod)
      pos = [coord(w.lat, 2), w.lat.negative? ? 'S' : 'N', coord(w.lon, 3), w.lon.negative? ? 'W' : 'E'].join(',')
      nmea_line(format('GPGGA,%s,%s,1,00,,%.1f,M,0.0,M,,0000', time, pos, w.alt)) +
        nmea_line(format('GPRMC,%s,A,%s,%06.2f,0.0,%s,,,E', time, pos, w.vel / 1.852, date.strftime('%d%m%y')))
    end.join
  end

  def file_name(number, date) = format('%05d_%s.nmea', number, date.strftime('%Y%m%d'))

  # Parses N, N-, N-M or -K against `count` tracks; returns a Range.
  def parse_range(arg, count)
    m = /\A(\d+)?(-)?(\d+)?\z/.match(arg.to_s)
    raise Error, "invalid track selection: #{arg}" if m.nil? || arg.empty? || arg == '-'

    a, dash, b = m[1]&.to_i, m[2], m[3]&.to_i
    range = if !dash then a..a
            elsif !a then (count - b)..(count - 1)
            elsif !b then a..(count - 1)
            else a..b
            end
    ok = range.begin >= 0 && range.begin <= range.end && range.end < count && (a || b.positive?)
    raise Error, "track selection #{arg} out of range (#{count} tracks)" unless ok

    range
  end

  # --- Serial protocol ---

  class Device
    def initialize(io, timeout: 1.0)
      @io = io
      @timeout = timeout
      @buf = ''.b
      @pos = 0
    end

    def self.open(dev)
      mode = File::RDWR | File::NOCTTY | File::BINARY # NOCTTY: never become our controlling terminal
      File.open(dev, mode).close
      system('stty', '-F', dev, '115200', 'cs8', '-parenb', '-cstopb', 'raw', '-echo',
             out: File::NULL, err: File::NULL) or raise Error, "#{dev}: stty failed"
      new(File.open(dev, mode))
    rescue SystemCallError => e
      raise Error, "#{dev}: #{e.message.sub(/ @ .*/, '')}"
    end

    def close = @io.close

    def send_command(body)
      @buf = ''.b
      @pos = 0
      drain
      @io.write(RGM3800.nmea_line(body))
      @io.flush
    end

    # Returns the next line body whose checksum is valid, or nil on timeout.
    def read_line
      line = nil
      while (c = getbyte)
        if line.nil?
          line = ''.b if c == 0x24 # '$'
          next
        end
        line << c
        if line.end_with?("\r\n") && line.bytesize >= 5 && line.getbyte(-5) == 0x2A # '*'
          body = line.byteslice(0, line.bytesize - 5)
          return body if format('%02X', body.bytes.reduce(0, :^)) == line.byteslice(-4, 2)
        end
        line = line.byteslice(-3..) if line.match?(/\r\n\$[A-Z]{3}\z/n) # a new line starts: drop the broken one
        line = nil if line.bytesize > 10_000
      end
    end

    def query(body, prefix)
      5.times do
        send_command(body)
        while (line = read_line)
          return line.split(',')[1..].map(&:to_i) if line.start_with?(prefix + ',')
        end
      end
      raise Error, "no response to #{body}"
    end

    def info = query('PROY108', 'LOG108')
    def memory = query('PROY100', 'LOG100')

    def track(n)
      date, format, count, address = query("PROY101,#{n}", 'LOG101')
      { number: n, date: Date.strptime(date.to_s, '%Y%m%d'), format: format, count: count, address: address }
    end

    def tracks = (0...info[7]).map { |n| track(n) }

    # Reads the raw records of track `n`, in chunks of at most 4800 bytes.
    # The logger only serves PROY102 for the track last selected with PROY101.
    def records(n)
      address, format, count = track(n).values_at(:address, :format, :count)
      len = RECORD_LEN.fetch(format)
      per = 4800 / len
      (0...count).step(per).flat_map do |i|
        yield i if block_given?
        chunk(address + (i * len), format, [per, count - i].min, len)
      end
    end

    def chunk(address, format, count, len)
      5.times do
        send_command("PROY102,#{address},#{format},#{count}")
        data = ''.b
        while data.bytesize < count * len && (line = read_line)
          payload = line.byteslice(10..).to_s
          data << payload if line.start_with?('LOG102,') && payload.bytesize == line.getbyte(9) && (payload.bytesize % len).zero?
        end
        return data.bytes.each_slice(len).map { |r| r.pack('C*') } if data.bytesize == count * len
      end
      raise Error, "reading #{count} records at #{address} failed after 5 tries"
    end

    # Erases all tracks, yielding progress lines; returns the tracks afterwards.
    # Done when no progress line arrives for 5 read timeouts; gives up after 10 minutes.
    # The logger keeps logging and may start a new track at once, so the erase counts
    # as done when fewer than `waypoints_before` waypoints remain.
    def erase(waypoints_before, limit: 600)
      raise Error, 'logger refused to erase' unless query('PROY109,-1', 'LOG109') == [1]

      start = last = now
      loop do
        line = read_line
        if line&.start_with?('PSRFTXT')
          last = now
          yield line if block_given?
        elsif now - last >= 5 * @timeout
          break
        end
        raise Error, 'erase did not finish within 10 minutes' if now - start > limit
      end
      left = nil
      5.times do # like PROY104, the logger may report the new state with a delay
        left = tracks
        break if left.empty? || left.sum { |t| t[:count] } < waypoints_before

        sleep @timeout
      end
      left
    end

    def configure(format, interval, memory_full)
      query("PROY104,0,#{interval},#{format},#{memory_full}", 'LOG104') == [1]
    end

    private

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def drain
      loop { @io.read_nonblock(65_536) }
    rescue IO::WaitReadable, EOFError
      nil
    end

    def getbyte
      if @pos >= @buf.bytesize
        return nil unless @io.wait_readable(@timeout)

        @buf = @io.readpartial(4096)
        @pos = 0
      end
      @pos += 1
      @buf.getbyte(@pos - 1)
    rescue EOFError
      nil
    end
  end

  # --- Command line ---

  USAGE = <<~TEXT
    Usage: rgm3800.rb [-d DEV] COMMAND [ARGS]

    Commands:
      info                         show logger configuration and memory usage
      list                         list the tracks on the logger
      download [-o DIR] [--fix-rollover] [RANGE]
                                   download tracks as NMEA files (RANGE: N, N-, N-M, -K);
                                   --fix-rollover adds 1024 weeks to the logger's dates
      config [--type 0|1|2] [--interval 5..60] [--memory-full overwrite|stop]
                                   change the logging configuration
      erase [--yes]                delete all tracks (asks first unless --yes)

    Options:
      -d DEV                       serial device (default /dev/ttyUSB0)
  TEXT

  def main(argv)
    dev = '/dev/ttyUSB0'
    OptionParser.new do |o|
      o.on('-d DEV') { |v| dev = v }
      o.on('-h', '--help') { puts USAGE; exit }
    end.order!(argv)
    cmd = argv.shift
    raise Error, "unknown command #{cmd.inspect}; see --help" unless %w[info list download config erase].include?(cmd)

    # Parse command options before touching the device.
    opts = {}
    case cmd
    when 'download'
      opts[:dir] = '.'
      opts[:range] = argv.pop if argv.last&.match?(/\A-\d+\z/) # -K would look like an option
      OptionParser.new do |o|
        o.on('-o DIR') { |v| opts[:dir] = v }
        o.on('--fix-rollover') { opts[:fix_rollover] = true }
      end.parse!(argv)
      opts[:range] ||= argv.shift
    when 'config' then opts = parse_config(argv)
    when 'erase' then OptionParser.new { |o| o.on('-y', '--yes') { opts[:yes] = true } }.parse!(argv)
    end
    raise Error, "unexpected argument #{argv.first}" unless argv.empty?

    dev = Device.open(dev)
    begin
      send("cmd_#{cmd}", dev, opts)
    ensure
      dev.close
    end
  end

  def parse_config(argv)
    opts = {}
    OptionParser.new do |o|
      o.on('--type N', Integer) { |v| opts[:format] = v }
      o.on('--interval N', Integer) { |v| opts[:interval] = v }
      o.on('--memory-full MODE') { |v| opts[:memory_full] = MEMORY_FULL.key(v) || v }
    end.parse!(argv)
    raise Error, "no settings given\n#{USAGE}" if opts.empty?
    raise Error, 'type must be 0-2 (only types 0-2 are supported)' if opts[:format] && !FORMAT_DESC.key?(opts[:format])
    raise Error, 'interval must be 5-60 seconds' if opts[:interval] && !(5..60).cover?(opts[:interval])
    raise Error, 'memory-full must be overwrite or stop' if opts[:memory_full] && !MEMORY_FULL.key?(opts[:memory_full])

    opts
  end

  def cmd_list(dev, _opts)
    dev.tracks.each do |t|
      puts format('%5d  %s  %6d waypoints  format %d', t[:number], t[:date], t[:count], t[:format])
    end
  end

  def cmd_download(dev, opts)
    tracks = dev.tracks
    return if tracks.empty? && opts[:range].nil?

    selected = opts[:range] ? tracks[parse_range(opts[:range], tracks.size)] : tracks
    failed = selected.reject { |t| FORMAT_DESC.key?(t[:format]) }
    failed.each { |t| warn "rgm3800: track #{t[:number]}: record format #{t[:format]} is not supported" }
    (selected - failed).each do |t|
      date = opts[:fix_rollover] ? t[:date] + ROLLOVER : t[:date]
      path = File.join(opts[:dir], file_name(t[:number], date))
      records = dev.records(t[:number]) do |i|
        $stderr.print "\rtrack #{t[:number]}: #{i}/#{t[:count]}"
      end
      text = nmea(records.filter_map { |r| decode(r, t[:format]) }, date)
      tmp = "#{path}.part"
      begin
        File.binwrite(tmp, text)
        File.rename(tmp, path)
      ensure
        File.unlink(tmp) if File.exist?(tmp)
      end
      warn "\rtrack #{t[:number]}: #{t[:count]} waypoints -> #{path}"
    end
    raise Error, "#{failed.size} track(s) not downloaded" unless failed.empty?
  end

  def config_text(info)
    format = info[0]
    ["data type    : #{format} (#{FORMAT_DESC.fetch(format, 'unsupported')})",
     "interval     : #{info[5]} s",
     "memory full  : #{MEMORY_FULL.fetch(info[3], info[3])}"]
  end

  def cmd_info(dev, _opts)
    info = dev.info
    total = dev.memory[0]
    used = dev.tracks.sum { |t| t[:count] * RECORD_LEN.fetch(t[:format], 0) }
    puts config_text(info)
    puts "tracks       : #{info[7]}"
    puts format('memory used  : %d of %d KB (%.1f%%)', used / 1024, total / 1024, used * 100.0 / total)
  end

  def cmd_config(dev, opts)
    info = dev.info
    want = [opts.fetch(:format, info[0]), opts.fetch(:interval, info[5]), opts.fetch(:memory_full, info[3])]
    ok = dev.configure(*want)
    got = nil
    5.times do # the logger applies the change within about a second
      sleep 0.5
      got = dev.info.values_at(0, 5, 3)
      break if got == want
    end
    unless ok && got == want
      raise Error, "configuration not accepted: requested type/interval/memory-full #{want.join('/')}, " \
                   "logger has #{got.join('/')}"
    end
    puts config_text(dev.info)
  end

  def cmd_erase(dev, opts)
    tracks = dev.tracks
    before = tracks.sum { |t| t[:count] }
    unless opts[:yes]
      tty = opts.fetch(:tty) { File.open('/dev/tty') rescue nil }
      raise Error, 'no terminal to ask for confirmation; use --yes' unless tty

      $stderr.print "Erase all #{tracks.size} tracks (#{before} waypoints)? [y/N] "
      raise Error, 'nothing erased' unless tty.gets.to_s.strip.match?(/\Ay(es)?\z/i)
    end
    left = dev.erase(before) { |line| $stderr.print "\r#{line.byteslice(0, 70)}" }
    warn ''
    after = left.sum { |t| t[:count] }
    if left.empty?
      puts 'logger is empty'
    elsif after < before
      puts "logger erased; it has started a new track (#{after} waypoints)"
    else
      raise Error, "erase finished but the logger still has #{after} waypoints (#{before} before)"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    RGM3800.main(ARGV)
  rescue RGM3800::Error, OptionParser::ParseError => e
    warn "rgm3800: #{e.message}"
    exit 1
  rescue Interrupt
    warn ""
    exit 130
  end
end
