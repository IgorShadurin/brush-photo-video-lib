defmodule Brush do
  def point(x, y), do: %{x: x * 1.0, y: y * 1.0}

  defp finite?(p), do: is_number(p.x) and is_number(p.y) and p.x == p.x and p.y == p.y
  defp clamp(value, low, high), do: min(high, max(low, value))
  defp distance(a, b) do
    dx = b.x - a.x
    dy = b.y - a.y
    :math.sqrt(dx * dx + dy * dy)
  end

  defp fmt(value) do
    rounded = Float.round(value * 1.0, 2)
    if rounded == 0 do
      "0"
    else
      rounded |> :erlang.float_to_binary(decimals: 2) |> String.trim_trailing("0") |> String.trim_trailing(".")
    end
  end

  defp fp(p), do: "#{fmt(p.x)} #{fmt(p.y)}"

  defp along(a, b, travel) do
    length = distance(a, b)
    if length == 0 do
      a
    else
      t = min(1, travel / length)
      point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    end
  end

  defp turn(a, b, c) do
    ux = b.x - a.x; uy = b.y - a.y
    vx = c.x - b.x; vy = c.y - b.y
    ul = :math.sqrt(ux * ux + uy * uy); vl = :math.sqrt(vx * vx + vy * vy)
    if ul == 0 or vl == 0, do: 0, else: :math.acos(clamp((ux * vx + uy * vy) / (ul * vl), -1, 1)) * 180 / :math.pi()
  end

  def build_rounded_drawing_path(input, font_size \\ 40) do
    points = Enum.filter(input, &finite?/1)
    case points do
      [] -> ""
      [value] -> "M #{fp(value)}"
      _ ->
        radius = max(12, font_size * 1.25)
        middle = points |> Enum.chunk_every(3, 1, :discard) |> Enum.map(fn [a, b, c] ->
          trim = min(radius, min(distance(a, b) * 0.45, distance(b, c) * 0.45))
          "L #{fp(along(b, a, trim))} Q #{fp(b)} #{fp(along(b, c, trim))}"
        end)
        Enum.join(["M " <> fp(hd(points))] ++ middle ++ ["L " <> fp(List.last(points))], " ")
    end
  end

  defp drawing(points, font_size) do
    Enum.reduce(points, nil, fn p, path ->
      if finite?(p) do
        cond do
          path == nil -> %{points: [p], d: "M " <> fp(p), font_size: font_size}
          distance(List.last(path.points), p) < 3 -> path
          length(path.points) == 1 or turn(Enum.at(path.points, -2), List.last(path.points), p) >= 18 ->
            retained = path.points ++ [p]
            %{points: retained, d: build_rounded_drawing_path(retained, font_size), font_size: font_size}
          true ->
            retained = List.replace_at(path.points, -1, p)
            %{points: retained, d: build_rounded_drawing_path(retained, font_size), font_size: font_size}
        end
      else
        path
      end
    end)
  end

  defp perpendicular(p, a, b) do
    dx = b.x - a.x; dy = b.y - a.y; squared = dx * dx + dy * dy
    if squared == 0 do
      distance(p, a)
    else
      t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / squared, 0, 1)
      distance(p, point(a.x + t * dx, a.y + t * dy))
    end
  end

  defp rdp(_points, first, last, _tolerance, keep) when last <= first + 1, do: keep
  defp rdp(points, first, last, tolerance, keep) do
    {best, index} = Enum.reduce((first + 1)..(last - 1), {0.0, -1}, fn i, {greatest, held} ->
      value = perpendicular(Enum.at(points, i), Enum.at(points, first), Enum.at(points, last))
      if value > greatest, do: {value, i}, else: {greatest, held}
    end)
    if best > tolerance do
      keep = MapSet.put(keep, index)
      keep = rdp(points, first, index, tolerance, keep)
      rdp(points, index, last, tolerance, keep)
    else
      keep
    end
  end

  defp simplify(points, _tolerance) when length(points) <= 2, do: points
  defp simplify(points, tolerance) do
    last = length(points) - 1
    keep = rdp(points, 0, last, tolerance, MapSet.new([0, last]))
    points |> Enum.with_index() |> Enum.filter(fn {_p, i} -> MapSet.member?(keep, i) end) |> Enum.map(&elem(&1, 0))
  end

  def prepare_arc_length_path(input, minimum \\ 0.5) do
    valid = Enum.filter(input, &finite?/1)
    filtered = Enum.reduce(valid, [], fn p, result ->
      if result == [] or distance(List.last(result), p) >= minimum, do: result ++ [p], else: result
    end)
    filtered = if valid != [] and filtered != [] and distance(List.last(filtered), List.last(valid)) > 0,
      do: filtered ++ [List.last(valid)], else: filtered
    points = simplify(filtered, max(minimum * 0.5, 0.1))
    {segments, total} = points |> Enum.chunk_every(2, 1, :discard) |> Enum.reduce({[], 0.0}, fn [a, b], {held, length} ->
      segment_length = distance(a, b)
      if segment_length > 0 do
        {held ++ [%{a: a, b: b, start: length, length: segment_length}], length + segment_length}
      else
        {held, length}
      end
    end)
    %{points: points, segments: segments, total_length: total}
  end

  defp point_at(path, requested) do
    distance_on_path = clamp(requested, 0, path.total_length)
    case Enum.find(path.segments, fn segment -> distance_on_path <= segment.start + segment.length end) do
      nil -> if path.segments == [], do: point(0, 0), else: List.last(path.segments).b
      segment ->
        t = clamp((distance_on_path - segment.start) / segment.length, 0, 1)
        point(segment.a.x + (segment.b.x - segment.a.x) * t, segment.a.y + (segment.b.y - segment.a.y) * t)
    end
  end

  def sample_at(path, progress, font_size \\ 40) do
    progress = clamp(progress, 0, 1)
    if path.total_length <= 0 do
      %{x: 0, y: 0, angle: 0, progress: progress}
    else
      target = path.total_length * progress
      window = max(min(max(font_size * 1.1, 0.75), path.total_length * 0.06), 0.75)
      a = point_at(path, target - window); b = point_at(path, target + window); p = point_at(path, target)
      %{x: p.x, y: p.y, angle: :math.atan2(b.y - a.y, b.x - a.x), progress: progress}
    end
  end

  def stable_repeated_text(text, font_size) do
    phrase = String.trim(text)
    if phrase == "" do
      ""
    else
      count = ceil(20_000 / max(font_size, String.length(phrase) * font_size * 0.62)) |> max(16) |> min(256)
      List.duplicate(phrase, count) |> Enum.join("   ")
    end
  end

  defp esc(value) do
    value |> to_string() |> String.replace("&", "&amp;") |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;") |> String.replace("\"", "&quot;") |> String.replace("'", "&apos;")
  end

  def render_svg(bytes, mime, width, height, points, text, supplied \\ %{}) do
    unless mime in ["image/png", "image/jpeg", "image/webp", "image/gif", "image/avif"], do: raise ArgumentError
    defaults = %{font_size: 40, font_family: "Arial, sans-serif", font_weight: "700", letter_spacing: nil,
      color: "#ffffff", magic_gradient: false, opacity: 1, stroke_color: "rgba(15,23,42,0.72)",
      stroke_width: 1.5, shadow: true, repeat_text: true, reveal_progress: 1}
    options = Map.merge(defaults, supplied); phrase = String.trim(text); path = drawing(points, options.font_size)
    if phrase == "" or path == nil or length(path.points) < 2, do: raise ArgumentError
    repeated = if options.repeat_text, do: stable_repeated_text(phrase, options.font_size), else: phrase
    gradient = if options.magic_gradient, do: "<linearGradient id=\"brush-gradient\" x1=\"100\" y1=\"150\" x2=\"900\" y2=\"850\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0%\" stop-color=\"#ec4899\"/><stop offset=\"20%\" stop-color=\"#f97316\"/><stop offset=\"40%\" stop-color=\"#facc15\"/><stop offset=\"60%\" stop-color=\"#10b981\"/><stop offset=\"80%\" stop-color=\"#3b82f6\"/><stop offset=\"100%\" stop-color=\"#8b5cf6\"/></linearGradient>", else: ""
    shadow = if options.shadow, do: "<filter id=\"brush-shadow\"><feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"2\" flood-color=\"#0f172a\" flood-opacity=\"0.65\"/></filter>", else: ""
    filter = if options.shadow, do: " filter=\"url(#brush-shadow)\"", else: ""
    fill = if options.magic_gradient, do: "url(#brush-gradient)", else: esc(options.color)
    spacing = options.letter_spacing || max(0.75, options.font_size * 0.06); reveal = clamp(options.reveal_progress, 0, 1)
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="#{fmt(width)}" height="#{fmt(height)}" viewBox="0 0 #{fmt(width)} #{fmt(height)}"><image width="#{fmt(width)}" height="#{fmt(height)}" preserveAspectRatio="xMidYMid slice" href="data:#{mime};base64,#{Base.encode64(bytes)}"/><defs><path id="brush-path" d="#{esc(path.d)}"/>#{gradient}#{shadow}<mask id="brush-reveal"><rect width="100%" height="100%" fill="black"/><path d="#{esc(path.d)}" pathLength="1" fill="none" stroke="white" stroke-width="#{fmt(options.font_size * 2.4)}" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="1" stroke-dashoffset="#{fmt(1 - reveal)}"/></mask></defs><g mask="url(#brush-reveal)" opacity="#{fmt(clamp(options.opacity, 0, 1))}"#{filter}><text font-family="#{esc(options.font_family)}" font-size="#{fmt(options.font_size)}" font-weight="#{esc(options.font_weight)}" letter-spacing="#{fmt(spacing)}" fill="#{fill}" stroke="#{esc(options.stroke_color)}" stroke-width="#{fmt(max(0, options.stroke_width))}" paint-order="stroke fill"><textPath href="#brush-path" xlink:href="#brush-path" startOffset="0" spacing="exact">#{esc(repeated)}</textPath></text></g></svg>
    """
  end
end
