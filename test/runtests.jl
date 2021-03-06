using BGZFStreams
using Base.Test
using Compat

@testset "VirtualOffset" begin
    voff = VirtualOffset(0, 0)
    @test voff == VirtualOffset(0, 0)
    @test voff != VirtualOffset(0, 1)
    @test voff <= VirtualOffset(0, 1)
    @test voff != VirtualOffset(1, 0)
    @test voff <= VirtualOffset(1, 0)
    @test voff[1] == 0
    @test voff[2] == 0
    @test string(voff) == "BGZFStreams.VirtualOffset(0, 0)"

    voff += 1
    @test voff[1] == 0
    @test voff[2] == 1

    voff = VirtualOffset(1234, 555)
    @test voff[1] == 1234
    @test voff[2] == 555
    @test string(voff) == "BGZFStreams.VirtualOffset(1234, 555)"

    @test_throws ArgumentError VirtualOffset(1 << 48, 0)
    @test_throws ArgumentError VirtualOffset(0, 1 << 16)
end

@testset "BGZFStream" begin
    filename = Pkg.dir("BGZFStreams", "test", "bar.bgz")
    stream = BGZFStream(filename, "r")
    @test read(stream, UInt8) === UInt8('b')
    @test read(stream, UInt8) === UInt8('a')
    @test read(stream, UInt8) === UInt8('r')
    @test eof(stream)
    @test flush(stream) === nothing
    @test close(stream) === nothing
    @test string(stream) == "BGZFStreams.BGZFStream{IOStream}(<mode=read>)"
    @test_throws ArgumentError read(stream, UInt8)

    stream = BGZFStream(filename, "r")
    data = zeros(Int8, 3)
    unsafe_read(stream, pointer(data), 3)
    @test data == UInt8['b', 'a', 'r']
    close(stream)
    @test_throws ArgumentError unsafe_read(stream, pointer(data), 3)

    stream = BGZFStream(filename, "r")
    @test virtualoffset(stream) === VirtualOffset(0, 0)
    read(stream, UInt8)
    read(stream, UInt8)
    @test virtualoffset(stream) === VirtualOffset(0, 2)
    seek(stream, VirtualOffset(0, 1))
    @test read(stream, UInt8) === UInt8('a')
    @test read(stream, UInt8) === UInt8('r')
    seekstart(stream)
    @test read(stream, UInt8) === UInt8('b')
    @test read(stream, UInt8) === UInt8('a')
    @test read(stream, UInt8) === UInt8('r')
    close(stream)

    # Empty data.
    empty_block = copy(BGZFStreams.EOF_BLOCK)
    stream = BGZFStream(IOBuffer(empty_block))
    @test_throws EOFError read(stream, UInt8)
    @test_throws EOFError read(stream, UInt8)
    stream = BGZFStream(IOBuffer(vcat(empty_block, empty_block)))
    @test_throws EOFError read(stream, UInt8)
    @test_throws EOFError read(stream, UInt8)
    stream = BGZFStream(IOBuffer(empty_block))
    @test isempty(read(stream))
    @test isempty(read(stream))
    stream = BGZFStream(IOBuffer(vcat(empty_block, empty_block)))
    @test isempty(read(stream))
    @test isempty(read(stream))

    filename = tempname()
    try
        stream = BGZFStream(filename, "w")
        @test virtualoffset(stream) == VirtualOffset(0, 0)
        @test write(stream, 'b') === 1
        @test write(stream, 'a') === 1
        @test write(stream, 'r') === 1
        @test virtualoffset(stream) == VirtualOffset(0, 3)
        @test write(stream, "baz") === 3
        @test eof(stream)
        @test flush(stream) === nothing
        @test close(stream) === nothing
        @test string(stream) == "BGZFStreams.BGZFStream{IOStream}(<mode=write>)"
    catch
        rethrow()
    finally
        if isfile(filename)
            rm(filename)
        end
    end

    buffer = IOBuffer()
    stream = BGZFStream(buffer, "w")
    write(stream, "foo")
    close(stream)
    @test !isopen(buffer)
    @test_throws ArgumentError write(stream, 0x01)

    # Round trip
    for n in [0, 1, 2, 5, 10, 50, 100, 10_000, 100_000, 1_000_000]
        data = rand(0x00:0xf0, n)

        # bulk read/write
        buffer = IOBuffer()
        stream = BGZFStream(buffer, "w")
        # HACK: do not close the buffer after the stream is closed
        stream.onclose = io -> nothing
        write(stream, data)
        close(stream)
        seekstart(buffer)
        stream = BGZFStream(buffer)
        @test data == read(stream)
        close(stream)

        # read/write byte by byte
        buffer = IOBuffer()
        stream = BGZFStream(buffer, "w")
        # HACK: do not close the buffer after the stream is closed
        stream.onclose = io -> nothing
        for x in data
            write(stream, x)
        end
        close(stream)
        seekstart(buffer)
        stream = BGZFStream(buffer)
        data′ = UInt8[]
        while !eof(stream)
            push!(data′, read(stream, UInt8))
        end
        @test data == data′
        close(stream)
    end
end
