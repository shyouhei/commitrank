#! /usr/bin/ruby
require 'svn/client'
require 'tempfile'

# (1) get the data
file = 'tmp.marshal'
dat = nil
begin
	open file, 'rb' do |fp|
		dat = Marshal.load fp
	end
rescue Errno::ENOENT
	dat = Hash.new

	Svn::Client::Context.new.log(
		"svn+ssh://some.svnsync.server.to.ruby.repo/repos",
		0, "head", 0, false, false
	) {|_, rev, who, wheen, what|
		t0 ||= wheen
		case who
		when NilClass, "svn"
			# skip
		else
			(dat[who] ||= []) << wheen
		end
	}
	open file, 'wb' do |fp|
		Marshal.dump dat, fp
	end
end

# (2) start computation
t = Time.now
t1 = t - 24 * 60 * 60 * 365
tmp = ''
IO.popen("gnuplot -bg white", "w") do |fp|

	# (3) preambles
	fp.print <<-'end'
		set key outside
		set xdata time
		set timefmt "%s"
		set datafile missing '?'
		set ytics (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192)
		set logscale y
		set term x11
		set title 'Committer ranking'
	end

	# (4) main loop
	c2p = dat.inject Hash.new do |r, (who, wheen)|

		# (5) ignore too old entry
		next r if wheen.last < t1

		
		fq = Tempfile.open tmp
		x = 0

		# (6) for each entries ...
		wheen.each_with_index do |i, k|
			next if wheen[k+1] and wheen[k+1] < t1
			x = 0

			# (7) accumulate commit counts (with attenuation)
			wheen.each do |j|
				break if j >= i
				x += Math.exp((j - i).to_f / 31556925.2507328)
			end

			# (8) print it.
			fq.printf "%d\t%f\n", i, x
			STDERR.printf "%p %s %f\r", i, who, x
		end

		# (9) last one
		x = 0
		wheen.each do |i|
			x += Math.exp((i - t).to_f / 31556925.2507328)
		end
		fq.printf "%d\t%f\n", t, x

		STDERR.puts
		fq.flush
		fq.close
		fq.open

		# (10) drop too low activists
		next r if x < 32
		str = sprintf '%8s:%7.2f', who, x
		r[str] = [x, fq]
		r
	end

	# (11) trailers
	fp.print <<-'end'
		set format x "%Y/%B"
		set xtics 7884000
		set mxtics 3
		set ylabel 'Attenuating integral of commit counts'
	end
	a = []
	c2p.sort_by {|(who, (siz, path))| - siz }.each do |(who, (siz, path))|
		a << sprintf("'%s' u 1:2 w l t '%s'", path.path, who)
	end

	# (12) kick gnuplot.
	# range e.g. 2010-Nov-01 -> Time.gm(1980-Nov-01).to_i
	fp.printf "plot[328665600.0:360201600.0][32:2048] %s\n", a.join(", ")
	fp.flush
	fp.write STDIN.gets
	fp.print <<-'end'
		set term svg fname 'M+ 2p' size 1366 768
		set output '/dev/shm/tmp2.svg'
		replot
	end
	fp.printf "quit\n"
	Process.waitpid fp.pid
end

# 
# Local Variables:
# mode: Ruby
# coding: utf-8-unix
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# fill-column: 79
# default-justification: full
# End:
# vi: ts=3 sw=3