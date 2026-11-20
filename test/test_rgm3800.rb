# frozen_string_literal: true

# Run with: ruby -Itest test/test_rgm3800.rb
require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'stringio'
require_relative '../rgm3800'

SAMPLE = ['01071224f66d5a3f69d7463d6e503dc22d4f8f42'].pack('H*')
FIXTURES = File.join(__dir__, 'fixtures', 'france')

class TestConversion < Minitest::Test
  def test_decode_format2
    w = RGM3800.decode(SAMPLE, 2)
    assert_equal [7, 18, 36], [w.h, w.m, w.s]
    assert_in_delta 0.8532404, w.lat, 1e-7
    assert_in_delta 0.0485453, w.lon, 1e-7
    assert_in_delta(-47.3285, w.alt, 1e-4)
    assert_in_delta 71.6546, w.vel, 1e-4
  end

  def test_decode_formats_0_and_1
    w = RGM3800.decode(SAMPLE[0, 12], 0)
    assert_equal [0.0, 0.0], [w.alt, w.vel]
    w = RGM3800.decode(SAMPLE[0, 16], 1)
    assert_in_delta(-47.3285, w.alt, 1e-4)
    assert_equal 0.0, w.vel
  end

  def test_decode_skips_invalid
    assert_nil RGM3800.decode("\x00".b + SAMPLE[1..], 2)
  end

  def test_decode_rejects_other_formats
    assert_raises(RGM3800::Error) { RGM3800.decode(SAMPLE + ("\0" * 4), 3) }
  end

  def test_format2_waypoint
    out = RGM3800.nmea([RGM3800.decode(SAMPLE, 2)], Date.new(2007, 2, 3))
    assert_equal "$GPGGA,071836.000,4853.2244,N,00246.8864,E,1,00,,-47.3,M,0.0,M,,0000*5C\r\n" \
                 "$GPRMC,071836.000,A,4853.2244,N,00246.8864,E,038.69,0.0,030207,,,E*5B\r\n", out
  end

  def test_format0_waypoint
    out = RGM3800.nmea([RGM3800.decode(SAMPLE[0, 12], 0)], Date.new(2007, 2, 3))
    assert_match(/,1,00,,0\.0,M,0\.0,M,,0000\*/, out)
    assert_match(/,E,000\.00,0\.0,030207,/, out)
  end

  def test_southern_western_hemispheres
    w = RGM3800::Waypoint.new(1, 2, 3, -0.8532404, -0.0485453, 0.0, 0.0)
    assert_match(/,4853\.\d{4},S,00246\.\d{4},W,/, RGM3800.nmea([w], Date.new(2007, 2, 3)))
  end

  def test_date_advances_when_time_decreases
    w = ->(h, m, s) { RGM3800::Waypoint.new(h, m, s, 0.1, 0.1, 0.0, 0.0) }
    out = RGM3800.nmea([w[23, 59, 22], w[0, 0, 22], w[0, 1, 22]], Date.new(2007, 2, 7))
    assert_equal %w[070207 080207 080207], out.scan(/,(\d{6}),,,E/).flatten
  end

  def test_reference_fixture
    skip 'private fixture test/fixtures/france/ not present' unless File.exist?(File.join(FIXTURES, 'raw.json'))
    tracks = JSON.parse(File.read(File.join(FIXTURES, 'raw.json')))
    assert_equal 2187, tracks.sum { |t| t['records'].size }
    tracks.each do |t|
      name = format('%05d_%s.nmea', t['number'], t['date'])
      official = File.binread(File.join(FIXTURES, name))
      ours = RGM3800.nmea(t['records'].map { |r| RGM3800.decode([r].pack('H*'), t['format']) },
                          Date.strptime(t['date'], '%Y%m%d'))
      if t['number'] == 4
        diff = ours.lines.zip(official.lines).reject { |a, b| a == b }
        assert_equal 87, diff.size
        diff.each do |a, b|
          fa = a.split(/[,*]/)
          fb = b.split(/[,*]/)
          assert_equal 'GPRMC', fa[0][1..]
          assert_operator fa[1], :>, '000022'
          assert_equal %w[080207 070207], [fa[9], fb[9]]
          assert_equal fa[0..8] + fa[10..-2], fb[0..8] + fb[10..-2]
        end
      else
        assert_equal official, ours, name
      end
    end
  end
end

# Fake serial port: each written command makes its canned reply readable.
class FakeIO
  attr_reader :written

  def initialize(replies)
    @replies = replies
    @written = []
    @in = ''.b
  end

  def write(data)
    @written << data
    reply = @replies[data[1...data.index('*')]]
    @in << (reply.respond_to?(:shift) ? reply.shift.to_s : reply.to_s).b
  end

  def flush; end
  def close; end
  def wait_readable(_timeout) = !@in.empty?

  def readpartial(_n)
    raise EOFError if @in.empty?

    @in.slice!(0, 7).tap { |s| s.force_encoding(Encoding::BINARY) }
  end

  def read_nonblock(_n) = raise(IO::EAGAINWaitReadable)
end

def line(body) = RGM3800.nmea_line(body.b).b

class TestProtocol < Minitest::Test
  def device(replies) = RGM3800::Device.new(FakeIO.new(replies), timeout: 0)

  def test_command_format
    io = FakeIO.new({})
    RGM3800::Device.new(io).send_command('PROY108')
    assert_equal ["$PROY108*2D\r\n"], io.written
  end

  def test_payload_containing_checksum_and_crlf
    body = "LOG102,\x00\x00\x01xx*41\r\nyy".b
    dev = device('X' => line(body))
    dev.send_command('X')
    assert_equal body, dev.read_line
  end

  def test_corrupted_line_is_discarded
    bad = line('LOG102,abc').sub('abc', 'abd')
    dev = device('X' => "noise#{bad}#{line('LOG108,2,0')}")
    dev.send_command('X')
    assert_equal 'LOG108,2,0', dev.read_line
    assert_nil dev.read_line
  end

  def test_queries
    dev = device('PROY108' => "#{line('GPGGA,junk')}#{line('LOG108,2,0,0,1,0,60,0,10,2')}",
                 'PROY100' => line('LOG100,8388608,65536,128'),
                 'PROY101,3' => line('LOG101,20070206,2,133,51200'))
    assert_equal [2, 0, 0, 1, 0, 60, 0, 10, 2], dev.info
    assert_equal [8_388_608, 65_536, 128], dev.memory
    assert_equal({ number: 3, date: Date.new(2007, 2, 6), format: 2, count: 133, address: 51_200 }, dev.track(3))
  end

  def test_query_gives_up
    assert_raises(RGM3800::Error) { device({}).info }
  end

  def test_chunked_records_with_retry
    recs = Array.new(300) { |i| [1, 0, 0, i % 60, 0.1, 0.2, 0.0, 0.0].pack('C4e4') }
    data = ->(rs) { rs.each_slice(12).with_index.map { |s, i| line("LOG102,#{[i, s.join.bytesize].pack('vC')}".b + s.join) }.join }
    replies = {
      'PROY101,0' => line('LOG101,20070203,2,300,1000'),
      'PROY102,1000,2,240' => [data[recs[0, 100]], data[recs[0, 240]]],
      'PROY102,5800,2,60' => [data[recs[240, 60]]]
    }
    dev = device(replies)
    assert_equal recs, dev.records(0)
  end

  def test_records_fail_after_retries
    assert_raises(RGM3800::Error) { device('PROY101,0' => line('LOG101,20070203,2,10,0')).records(0) }
  end
end

class TestCLI < Minitest::Test
  def test_parse_range
    assert_equal 3..3, RGM3800.parse_range('3', 10)
    assert_equal 7..9, RGM3800.parse_range('7-', 10)
    assert_equal 7..9, RGM3800.parse_range('7-9', 10)
    assert_equal 8..9, RGM3800.parse_range('-2', 10)
    %w[10 x 3-2 -0 -11 9-10 - 1-2-3].push('').each do |bad|
      assert_raises(RGM3800::Error, bad) { RGM3800.parse_range(bad, 10) }
    end
  end

  def test_config_validation
    [%w[--interval 1], %w[--interval 61], %w[--type 3], %w[--type 4], %w[--memory-full sometimes], []].each do |args|
      assert_raises(RGM3800::Error, args.inspect) { RGM3800.parse_config(args) }
    end
    assert_equal({ format: 1, memory_full: 0 }, RGM3800.parse_config(%w[--type 1 --memory-full overwrite]))
  end

  def test_config_sends_nothing_when_invalid
    out = `#{RbConfig.ruby} #{File.join(__dir__, '..', 'rgm3800.rb')} -d /nonexistent config --type 4 2>&1`
    refute $?.success?
    assert_match(/only types 0-2/, out)
  end

  def test_download_rejects_unsupported_format
    dev = RGM3800::Device.new(FakeIO.new('PROY108' => line('LOG108,4,0,0,1,0,60,0,1,5'),
                                         'PROY101,0' => line('LOG101,20070203,4,5,0')), timeout: 0)
    Dir.mktmpdir do |dir|
      e = nil
      _, err = capture_io { e = assert_raises(RGM3800::Error) { RGM3800.cmd_download(dev, dir: dir) } }
      assert_match(/track 0: record format 4 is not supported/, err)
      assert_match(/1 track/, e.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_list_empty_logger
    dev = RGM3800::Device.new(FakeIO.new('PROY108' => line('LOG108,2,0,0,1,0,60,0,0,0')), timeout: 0)
    assert_output('') { RGM3800.cmd_list(dev, {}) }
  end
end

class TestErase < Minitest::Test
  BEFORE = 'LOG108,2,0,0,1,0,60,0,2,5'
  AFTER = 'LOG108,2,0,0,1,0,60,0,0,0'

  def logger(log109: line('LOG109,1'), after: AFTER, track0_after: 'LOG101,20070406,2,1,0')
    progress = (1..3).map { |i| line("PSRFTXTSFAM Test Report: #{i}") }.join
    FakeIO.new('PROY108' => [line(BEFORE)] + ([line(after)] * 5),
               'PROY101,0' => [line('LOG101,20070203,2,3,0')] + ([line(track0_after)] * 5),
               'PROY101,1' => line('LOG101,20070204,2,2,60'),
               'PROY109,-1' => [log109.to_s + progress])
  end

  def erase(io, opts)
    out, err = capture_io { RGM3800.cmd_erase(RGM3800::Device.new(io, timeout: 0), opts) }
    [out, err, io.written.grep(/PROY109/).size]
  end

  def test_erase_with_yes
    out, err, sent = erase(logger, yes: true)
    assert_equal "logger is empty\n", out
    assert_match(/Test Report: 3/, err)
    assert_equal 1, sent
  end

  def test_confirm_accepts_y_and_yes
    ["y\n", "YES\n", " Yes \n"].each do |answer|
      _, err, sent = erase(logger, tty: StringIO.new(answer))
      assert_match(/\AErase all 2 tracks \(5 waypoints\)\? \[y\/N\] /, err)
      assert_equal 1, sent, answer
    end
  end

  def test_decline_sends_nothing
    ["n\n", "\n", 'yy', ''].each do |answer|
      io = logger
      e = assert_raises(RGM3800::Error, answer.inspect) do
        capture_io { RGM3800.cmd_erase(RGM3800::Device.new(io, timeout: 0), tty: StringIO.new(answer)) }
      end
      assert_equal 'nothing erased', e.message
      assert_empty io.written.grep(/PROY109/)
    end
  end

  def test_no_terminal
    io = logger
    e = assert_raises(RGM3800::Error) { RGM3800.cmd_erase(RGM3800::Device.new(io, timeout: 0), tty: nil) }
    assert_match(/--yes/, e.message)
    assert_empty io.written.grep(/PROY109/)
  end

  def test_erase_refused
    e = assert_raises(RGM3800::Error) { erase(logger(log109: line('LOG109,0')), yes: true) }
    assert_match(/refused/, e.message)
  end

  def test_erase_no_reply
    e = assert_raises(RGM3800::Error) { erase(logger(log109: nil), yes: true) }
    assert_match(/no response to PROY109/, e.message)
  end

  def test_cli_rejects_arguments_before_device_access
    script = File.join(__dir__, '..', 'rgm3800.rb')
    out = `#{RbConfig.ruby} #{script} -d /nonexistent erase extra 2>&1`
    refute $?.success?
    assert_match(/unexpected argument extra/, out) # not "No such file": the device was not opened
    assert_match(/erase \[--yes\]/, `#{RbConfig.ruby} #{script} --help`)
  end

  def test_new_track_after_erase
    out, = erase(logger(after: 'LOG108,2,0,0,1,0,60,0,1,1'), yes: true)
    assert_equal "logger erased; it has started a new track (1 waypoints)\n", out
  end

  def test_tracks_remain
    e = assert_raises(RGM3800::Error) do
      erase(logger(after: 'LOG108,2,0,0,1,0,60,0,1,5', track0_after: 'LOG101,20070203,2,5,0'), yes: true)
    end
    assert_match(/still has 5 waypoints \(5 before\)/, e.message)
  end
end
