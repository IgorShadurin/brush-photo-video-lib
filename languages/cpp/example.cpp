#include "brush.hpp"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
int main(int argc,char**argv){using brush::Point;std::vector<Point>p={{500,520},{450,450},{390,395},{320,370},{250,370},{180,390},{130,450},{120,520},{155,585},{220,635},{300,650},{380,620},{440,570},{500,520},{560,465},{620,410},{700,370},{770,380},{830,420},{870,480},{875,545},{845,610},{790,660},{720,675},{650,655},{585,610},{540,560},{500,520}};assert(brush::buildRoundedDrawingPath({{0,0},{100,0},{100,100}},40)=="M 0 0 L 55 0 Q 100 0 100 45 L 100 100");assert(brush::sampleAt(brush::prepareArcLengthPath({{0,0},{100,0}}),.5).angle==0);std::string input=argc>1?argv[1]:"assets/example.webp",output=argc>2?argv[2]:"generated/cpp.svg";std::ifstream in(input,std::ios::binary);std::vector<std::uint8_t>bytes((std::istreambuf_iterator<char>(in)),{});brush::Options o;o.magicGradient=true;auto svg=brush::renderSvg(bytes,"image/webp",1000,1000,p,"🤝 best friends forever",o);std::filesystem::create_directories(std::filesystem::path(output).parent_path());std::ofstream(output)<<svg;std::cout<<"Wrote "<<output<<"\n";}
