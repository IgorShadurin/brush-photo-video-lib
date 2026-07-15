Code.require_file("brush.ex", __DIR__)
p = &Brush.point/2
points = Enum.map([{500,520},{450,450},{390,395},{320,370},{250,370},{180,390},{130,450},{120,520},{155,585},{220,635},{300,650},{380,620},{440,570},{500,520},{560,465},{620,410},{700,370},{770,380},{830,420},{870,480},{875,545},{845,610},{790,660},{720,675},{650,655},{585,610},{540,560},{500,520}], fn {x, y} -> p.(x, y) end)
unless Brush.build_rounded_drawing_path([p.(0,0),p.(100,0),p.(100,100)],40) == "M 0 0 L 55 0 Q 100 0 100 45 L 100 100", do: raise "check"
[input, output] = case System.argv() do
  [a, b | _] -> [a, b]
  _ -> ["assets/example.webp", "generated/elixir.svg"]
end
svg = Brush.render_svg(File.read!(input), "image/webp", 1000, 1000, points, "🤝 best friends forever", %{magic_gradient: true})
File.mkdir_p!(Path.dirname(output)); File.write!(output, svg); IO.puts("Wrote #{output}")
