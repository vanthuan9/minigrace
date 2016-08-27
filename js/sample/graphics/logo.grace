// Logo-like dialect
// This dialect provides turtle graphics, embedded in Grace syntax but
// using only statements of what should happen. The turtle module
// handles the actual drawing and user interface.
import "turtle" as turtle
inherits prelude
type Point = prelude.Point

def red is public = turtle.red
def green is public = turtle.green
def blue is public = turtle.blue
def black is public = turtle.black

var lineWidth is public := 1
var lineColor is public := black

method forward(dist) {
    turtle.move(dist, lineColor, lineWidth)
}
method turnRight(ang) {
    turtle.turnRight(ang)
}
method turnLeft(ang) {
    turtle.turnLeft(ang)
}
method penUp {
    turtle.penUp
}
method penDown {
    turtle.penDown
}
method speed:=(sp) {
    if (sp >= 1) then {
        turtle.speed := sp.floor
    }
}

//Method to create a pop-up canvas
method createCanvas(size:Point)
{
     turtle.useCanvas(size)
}

def thisDialect is public = object {
    method atEnd(mod) {
        turtle.start
    }
}
