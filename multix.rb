require 'delegate'

class Multix
  class Node < SimpleDelegator
    def initialize(o)
      super(o)
    end

    def _iterators
      @iterators ||= {}
    end

    def succ(key = :seq)
      @iterators[key].succ
    end
    alias :next :succ

    def prev(key = :seq)
      @iterators[key].prev
    end
  end

  def initialize(*indexes)
    @indexes = {}
    indexes.each do |index|
      @indexes[index.key] = index
    end
  end

  def by(key)
    @indexes[key].enum
  end

  def push(o)
    @indexes.each do |key, index|
      unless index.can_push?(o)
        return nil
      end
    end

    n = Node.new(o)
    @indexes.each do |key, index|
      index.push(n)
    end
    n
  end
  alias :<< :push

  def delete(n)
    @indexes.each do |key, index|
      index.delete(n)
    end
  end

  class Collection
    attr_reader :key

    def can_push?(o)
      true
    end
  end

  class Sequenced < Collection
    include Enumerable

    class Node
      attr_accessor :nxt, :prv, :o

      def initialize(o)
        @o = o
      end

      def succ
        nxt.o
      end

      def prev
        prv.o
      end
    end

    def initialize(key)
      @key = key
      @head = nil
      @tail = nil
    end

    def push(o)
      n = Node.new(o)
      o._iterators[@key] = n
      if @tail
        n.prv = @tail
        @tail.nxt = n
        @tail = n
      else
        @head = @tail = n
      end
    end

    def delete(o)
      n = o._iterators[@key]
      prv = n.prv
      nxt = n.nxt
      prv.nxt = nxt
      nxt.prv = prv
    end

    def enum
      self
    end

    def each
      n = @head
      while n
        yield n.o
        n = n.nxt
      end
    end
  end

  def self.sequenced(key = :seq)
    Sequenced.new(key)
  end

  class Hashed < Collection
    def initialize(key)
      @hash = Hash.new
      @key = key
      def self.push(o)
        @hash[o.send(@key)] = o
      end
    end

    def delete(o)
      @hash.delete(o.send(@key))
    end

    def can_push?(o)
      !@hash.has_key?(o.send(@key))
    end

    def enum
      @hash
    end
  end

  def self.hashed(key)
    Hashed.new(key)
  end

  class Ordered < Collection
    include Enumerable

    class Node
      attr_accessor :left, :right, :parent, :o

      def initialize(o)
        @o = o
      end

      def succ
        if @right
          c = @right
          while c.left
            c = c.left
          end
        else
          n = self
          c = @parent
          while c
            if n == c.left
              break
            end
            n = c
            c = n.parent
          end
        end
        c ? c.o : nil
      end

      def prev
        if @left
          c = @left
          while c.right
            c = c.right
          end
        else
          n = self
          c = @parent
          while c
            if n == c.right
              break
            end
            n = c
            c = n.parent
          end
        end
        c ? c.o : nil
      end
    end

    def initialize(key)
      @key = key
      @root = nil
    end

    def push(o)
      n = Node.new(o)
      o._iterators[@key] = n
      key = o.send(@key)
      if @root
        c = @root
        while true
          k = c.o.send(@key)
          if key < k
            if c.left
              c = c.left
            else
              c.left = n
              break
            end
          # For unique tree.
          #elsif key > k
          elsif key >= k
            if c.right
              c = c.right
            else
              c.right = n
              break
            end
          else
            # TODO
            return
          end
        end

        n.parent = c

        _splay(n)
      else
        @root = n
      end

      #begin
      #  _validate
      #rescue
      #  puts $!
      #end
    end

    def [](key)
      n = _fetch_node(key)
      n ? n.o : nil
    end

    def has_key?(key)
      n = _fetch_node(key)
      n != nil
    end

    def delete(o)
      n = o._iterators[@key]
      if n.left
        c = n.left
        if c.right
          while c.right
            c = c.right
          end

          _set_right(c.parent, c.left)
          _set_left(c, n.left)
        end
        _set_right(c, n.right)
      else
        c = n.right
      end

      _set_parent(c, n)
      if @root == n
        @root = c
      else
        _splay(c.parent)
      end
    end

    def enum
      self
    end

    def each
      n = @root
      while n.left
        n = n.left
      end

      st = :dr
      while n
        yield n.o

        while true
          #STDERR.puts "#{n.o.val} #{st}"

          case st
          when :up
            c = n
            n = n.parent
            unless n
              return
            end

            if c == n.left
              st = :dr
              break
            elsif c == n.right
            else
              raise 'internal error: broken tree'
            end
          when :dr
            if n.right
              n = n.right
              st = :dl
            else
              st = :up
            end
          when :dl
            if n.left
              n = n.left
              st = :dl
            else
              st = :dr
              break
            end
          end
        end
      end
    end

    if __FILE__ == $0
      def dump
        dump_node(@root, 0, 'X')
      end

      def dump_node(n, depth, type)
        return unless n
        puts " " * depth + type + n.o.to_s + "\t#{n.parent ? n.parent.o : 'nil'}"
        dump_node(n.left, depth + 1, 'L')
        dump_node(n.right, depth + 1, 'R')
      end
    end

    private

    def _validate
      raise 'validation failure' unless @root
      raise 'validation failure' if @root.parent
      _validate_node(@root)
    end

    def _validate_node(n)
      if n.left
        raise 'validation failure' if n.left.o.send(@key) > n.o.send(@key)
        raise 'validation failure' if n.left.parent != n
        _validate_node(n.left)
      end
      if n.right
        raise 'validation failure' if n.right.o.send(@key) < n.o.send(@key)
        raise 'validation failure' if n.right.parent != n
        _validate_node(n.right)
      end
    end

    def _fetch_node(key)
      c = @root
      unless c
        return nil
      end

      while true
        k = c.o.send(@key)
        if key < k
          if c.left
            c = c.left
          else
            _splay(c)
            return nil
          end
        elsif key > k
          if c.right
            c = c.right
          else
            _splay(c)
            return nil
          end
        else
          _splay(c)
          return c
        end
      end
    end

    def _set_parent(n, o, m = o.parent)
      if n
        n.parent = m
      end
      if m
        if m.left == o
          m.left = n
        elsif m.right == o
          m.right = n
        else
          raise 'internal error: broken tree'
        end
      end
    end

    def _set_left(n, c)
      n.left = c
      c.parent = n if c
    end

    def _set_right(n, c)
      n.right = c
      c.parent = n if c
    end

    def _splay(n)
      #until n == @root
        _splay_step(n)
      #end
    end

    def _splay_step(n)
      if @root == n
        return
      end

      m = n.parent
      if @root == m
        if m.left == n
          # zig
          _set_left(m, n.right)
          n.right = m
        elsif m.right == n
          # zag
          _set_right(m, n.left)
          n.left = m
        else
          raise 'TODO'
        end
        n.parent = m.parent
        m.parent = n
        @root = n
      else
        g = m.parent
        if m.left == n
          if g.left == m
            # zig-zig
            _set_left(g, m.right)
            m.right = g
            _set_left(m, n.right)
            n.right = m
            _set_parent(n, g)
            m.parent = n
            g.parent = m
          elsif g.right == m
            # zag-zig
            _set_left(m, n.right)
            _set_right(g, n.left)
            n.right = m
            n.left = g
            _set_parent(n, g)
            m.parent = n
            g.parent = n
          else
            raise 'TODO'
          end
        elsif m.right == n
          if g.left == m
            # zig-zag
            _set_right(m, n.left)
            _set_left(g, n.right)
            n.left = m
            n.right = g
            _set_parent(n, g)
            m.parent = n
            g.parent = n
          elsif g.right == m
            # zag-zag
            _set_right(g, m.left)
            m.left = g
            _set_right(m, n.left)
            n.left = m
            _set_parent(n, g)
            m.parent = n
            g.parent = m
          else
            raise 'TODO'
          end
        end

        unless n.parent
          @root = n
        end
      end
    end
  end

  def self.ordered(key)
    Ordered.new(key)
  end
end

def Multix(*a)
  Multix.new(*a)
end

if __FILE__ == $0

  require 'test/unit'

  class TestMultix < Test::Unit::TestCase

    class Presen
      attr_accessor :twitter_id, :hatena_id, :title
      def initialize(twitter_id, hatena_id, title)
        @twitter_id = twitter_id
        @hatena_id = hatena_id
        @title = title
      end
    end

    def test_multix
      m = Multix(Multix.sequenced,
                 Multix.ordered(:twitter_id),
                 Multix.hashed(:hatena_id))
      m.push(Presen.new('cpp_akira', 'faith_and_brave', 'Boost issyuu'))
      m.push(Presen.new('kinaba', 'cafelier', 'Boost.MultiIntrusivedex'))
      foo = m.push(Presen.new('foo', 'bar', 'baz'))
      m.push(Presen.new('melponn', 'melpon', 'Boost.Coroutine'))

      assert_equal('foo', foo.twitter_id)

      assert_equal('faith_and_brave', m.by(:twitter_id)['cpp_akira'].hatena_id)
      assert_equal('kinaba', m.by(:hatena_id)['cafelier'].twitter_id)

      assert_equal('baz', m.by(:twitter_id)['foo'].title)
      assert_equal('baz', m.by(:hatena_id)['bar'].title)
      assert_equal('baz', m.by(:seq).to_a[2].title)

      foo = m.by(:twitter_id)['foo']
      succ = foo.succ(:seq)
      m.delete(foo)
      # Deleted element.
      assert_nil(m.by(:twitter_id)['foo'])
      assert_nil(m.by(:hatena_id)['bar'])
      assert_equal('Boost.Coroutine', m.by(:seq).to_a[2].title)

      assert_equal('melponn', succ.twitter_id)

      assert_not_nil(m.push(Presen.new('foo', 'bar', 'baz')))
      assert_nil(m.push(Presen.new('foo', 'bar', 'baz')))
      assert_nil(m.push(Presen.new('foo2', 'bar', 'baz2')))
      assert_not_nil(m.push(Presen.new('foo', 'bar2', 'baz2')))

      a = m.by(:hatena_id).map{|k, o|o.twitter_id}
      b = m.by(:twitter_id).map{|o|o.twitter_id}
      assert_equal(a.size, b.size)
      assert_equal(a.sort, b)
      assert_equal(["cpp_akira", "foo", "foo", "kinaba", "melponn"], b)

      kinaba = m.by(:twitter_id)['kinaba']
      melponn = kinaba.succ(:twitter_id)
      assert_equal('melponn', melponn.twitter_id)
    end

    class Num
      attr_accessor :val

      def initialize(v)
        @val = v
      end

      def to_s
        @val.to_s
      end

      def inspect
        @val.inspect
      end
    end

    def test_ordered
      num = 100

      m = Multix(Multix.ordered(:val))
      (0..num).sort_by{rand}.each do |v|
        m.push(Num.new(v))

        #puts
        #m.by(:val).dump
      end

      #m.by(:val).dump

      m.by(:val).each_with_index do |v, i|
        assert_equal(i, v.val)
      end

      num.times do |i|
        assert_equal(i, m.by(:val)[i].val)
      end
      #m.by(:val).dump
      (0...num).sort_by{rand}.each do |i|
        assert_equal(i, m.by(:val)[i].val)
      end

      #m.by(:val).dump
      m.delete(m.by(:val)[num])
      #m.by(:val).dump
      assert_nil(m.by(:val)[num])

      (num/2...num).sort_by{rand}.each do |v|
        #p v
        #m.by(:val).dump
        m.delete(m.by(:val)[v])
      end

      a = m.by(:val).map{|v|v.val}
      assert_equal(num / 2, a.size)
      (num/2).times do |i|
        assert_equal(i, a[i])
      end

      b = []
      iter = m.by(:val)[0]
      assert_not_nil(iter)
      assert_nil(iter.prev(:val))
      while iter
        b << iter.val
        iter = iter.succ(:val)
      end
      assert_equal(a, b)

      c = []
      iter = m.by(:val)[num/2-1]
      assert_not_nil(iter)
      assert_nil(iter.succ(:val))
      while iter
        c << iter.val
        iter = iter.prev(:val)
      end
      assert_equal(a, c.reverse)

      (num/2).times do |i|
        assert_equal(i, m.push(Num.new(i)).val)
      end

      a = m.by(:val).to_a
      assert_equal(num, a.size)
      num.times do |i|
        assert_equal(i / 2, a[i].val)
      end
    end
  end
end
