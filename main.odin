package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:slice"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

App :: struct {
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    event: SDL.Event,

    font: ^TTF.Font,
    pixel: ^SDL.Texture,
    pixels: [SCREEN_WIDTH * SCREEN_HEIGHT]u32,
    angle_x: f32,
    angle_y: f32,
    angle_z: f32,
}

SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 560

FONT_SIZE :: 40

Vec2i :: [2]i32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: [4][4]f32
Face :: [4]int

face_colors := [6]u32{
    0xFF0000FF, // red
    0x00FF00FF, // green
    0x0000FFFF, // blue
    0xFFFF00FF, // yellow
    0xFF00FFFF, // magenta
    0x00FFFFFF, // cyan
}

cube_vertices := [8]Vec3 {
    {-0.5, -0.5, -0.5},
    { 0.5, -0.5, -0.5},
    { 0.5,  0.5, -0.5},
    {-0.5,  0.5, -0.5},
    {-0.5, -0.5,  0.5},
    { 0.5, -0.5,  0.5},
    { 0.5,  0.5,  0.5},
    {-0.5,  0.5,  0.5}
}

cube_edges := [12][2]int {
    {0, 1}, {1, 2}, {2, 3}, {3, 0}, // front face
    {4, 5}, {5, 6}, {6, 7}, {7, 4}, // back face
    {0, 4}, {1, 5}, {2, 6}, {3, 7}, // connecting edges
}

faces := [6]Face {
    {0, 1, 2, 3},
    {4, 5, 6, 7},
    {0, 3, 7, 4},
    {0, 1, 5, 4},
    {1, 2, 6, 5},
    {3, 2, 6, 7},
}

FaceDepth :: struct {
    face: Face,
    depth: f32,
}

initialize :: proc(app: ^App) -> bool {
    TTF.Init()

    app.window = SDL.CreateWindow("3D Renderer", SCREEN_WIDTH, SCREEN_HEIGHT, {})
    if app.window == nil {
        log.error("Failed to create window:", SDL.GetError())
        return false
    }

    app.renderer = SDL.CreateRenderer(app.window, nil)
    if app.renderer == nil {
        log.error("Failed to create renderer:", SDL.GetError())
        return false
    }

    app.font = TTF.OpenFont("fonts/ShareTechMono-Regular.ttf", FONT_SIZE)
    if app.font == nil {
        log.error("Failed to load font:", SDL.GetError())
        return false
    }

    SDL.SetRenderVSync(app.renderer, 1)

    create_framebuffer(app)

    return true
}

create_framebuffer :: proc(app: ^App) {
    // .Streaming manes that the texture will be updated every frame with the new pixel data
    app.pixel = SDL.CreateTexture(app.renderer, SDL.PixelFormat.RGBA8888, SDL.TextureAccess.STREAMING, SCREEN_WIDTH, SCREEN_HEIGHT)
    
    for i in 0..<SCREEN_WIDTH * SCREEN_HEIGHT {
        app.pixels[i] = 0xFF0000FF
    }
}

draw_pixel :: proc(app: ^App, x: int, y: int, color: u32) {
    if x < 0 || x >= SCREEN_WIDTH || y < 0 || y >= SCREEN_HEIGHT {
        return
    }
    app.pixels[y * SCREEN_WIDTH + x] = color
}

rotation_matrix_around_y_axis :: proc(angle: f32) -> Mat4 {
    rad := angle * math.PI / 180.0
    cosA := math.cos(rad)
    sinA := math.sin(rad)

    return Mat4 {
        {cosA,  0, sinA, 0},
        {0,     1, 0,    0},
        {-sinA, 0, cosA, 0},
        {0,     0, 0,    1},
    }
}

rotation_matrix_around_x_axis :: proc(angle: f32) -> Mat4 {
    rad := angle * math.PI / 180.0
    cosA := math.cos(rad)
    sinA := math.sin(rad)

    return Mat4 {
        {1, 0,    0,     0},
        {0, cosA, -sinA, 0},
        {0, sinA, cosA,  0},
        {0, 0,    0,     1},
    }
}

rotation_matrix_around_z_axis :: proc(angle: f32) -> Mat4 {
    rad := angle * math.PI / 180.0
    cosA := math.cos(rad)
    sinA := math.sin(rad)

    return Mat4 {
        {cosA, -sinA, 0, 0},
        {sinA, cosA,  0, 0},
        {0,    0,     1, 0},
        {0,    0,     0, 1},
    }
}

transform_vertex :: proc(v: Vec3, m: Mat4) -> Vec3 {
    return Vec3{
        v[0] * m[0][0] + v[1] * m[1][0] + v[2] * m[2][0],
        v[0] * m[0][1] + v[1] * m[1][1] + v[2] * m[2][1],
        v[0] * m[0][2] + v[1] * m[1][2] + v[2] * m[2][2],
    }
}

transform_vertex_4 :: proc(v: Vec4, m: Mat4) -> Vec4 {
    return Vec4 {
        v[0] * m[0][0] + v[1] * m[1][0] + v[2] * m[2][0] + v[3] * m[3][0],
        v[0] * m[0][1] + v[1] * m[1][1] + v[2] * m[2][1] + v[3] * m[3][1],
        v[0] * m[0][2] + v[1] * m[1][2] + v[2] * m[2][2] + v[3] * m[3][2],
        v[0] * m[0][3] + v[1] * m[1][3] + v[2] * m[2][3] + v[3] * m[3][3],
    }
}

perspective_matrix :: proc(fov, aspect, near, far: f32) -> Mat4 {
    fov_rad := fov * math.PI / 180.0
    focal_length := 1.0 / math.tan(fov_rad / 2.0)
    depth_a := -(far + near) / (far - near)
    depth_b := -(2.0 * far * near) / (far - near)

    return Mat4 {
        {focal_length / aspect, 0, 0, 0},
        {0, focal_length, 0, 0},
        {0, 0, depth_a, -1},
        {0, 0, -depth_b, 0} 
    }
}

calculate_face_depth :: proc(faces: Face, rot: Mat4) -> f32 { 
    z_values: f32
    face_value: Vec3
    transformed_vertex: Vec3

    for face in faces {
        face_value = cube_vertices[face]
        transformed_vertex = transform_vertex(face_value, rot)
        z_values += transformed_vertex[2]
    }

    return z_values / 4
}

fill_triangle :: proc(app: ^App, v0, v1, v2: Vec2i, color: u32) {
    // find bounding box
    min_x := min(v0[0], min(v1[0], v2[0]))
    min_y := min(v0[1], min(v1[1], v2[1]))
    max_x := max(v0[0], max(v1[0], v2[0]))
    max_y := max(v0[1], max(v1[1], v2[1]))

    // loop over every pixel in the bounding box
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            // edge function - checks which side of each edge the pixel is on
            w0 := (v1[0]-v0[0])*(y-v0[1]) - (v1[1]-v0[1])*(x-v0[0])
            w1 := (v2[0]-v1[0])*(y-v1[1]) - (v2[1]-v1[1])*(x-v1[0])
            w2 := (v0[0]-v2[0])*(y-v2[1]) - (v0[1]-v2[1])*(x-v2[0])

            // pixel is inside triangle if all edge functions have the same sign
            if (w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0) {
                draw_pixel(app, int(x), int(y), color)
            }
        }
    }
}

project_and_draw :: proc(app: ^App, angleX, angleY, angleZ: f32) {
    screen_x1: i32
    screen_y1: i32
    screen_x2: i32
    screen_y2: i32
    per := perspective_matrix(75.0, f32(SCREEN_WIDTH) / f32(SCREEN_HEIGHT), 0.1, 100.0)
    rotX := rotation_matrix_around_x_axis(angleX)
    rotY := rotation_matrix_around_y_axis(angleY)
    rotZ := rotation_matrix_around_z_axis(angleZ)
    rotXY := matrix_multiply(rotX, rotY)
    rot := matrix_multiply(rotXY, rotZ)

    face_depth_array: [6]FaceDepth

    for i in 0..<6 {
        face_depth_array[i].face = faces[i] 
        face_depth_array[i].depth = calculate_face_depth(faces[i], rot)
    }
    
    slice.sort_by(face_depth_array[:], proc(a, b: FaceDepth) -> bool {
        return a.depth > b.depth
    })

    for i in 0..<6 {
        verts := [4]Vec3 {
            cube_vertices[face_depth_array[i].face[0]],
            cube_vertices[face_depth_array[i].face[1]],
            cube_vertices[face_depth_array[i].face[2]],
            cube_vertices[face_depth_array[i].face[3]],
        }

        // project all 4 vertices to screen space
    screen_verts: [4]Vec2i
    for j in 0..<4 {
        v := transform_vertex(verts[j], rot)
        v[2] += 3.0
        v4 := Vec4{v[0], v[1], v[2], 1.0}
        p := transform_vertex_4(v4, per)
        px := p[0] / p[3]
        py := p[1] / p[3]
        screen_verts[j] = Vec2i{
            i32((px + 1.0) * f32(SCREEN_WIDTH) / 2.0),
            i32((1.0 - py) * f32(SCREEN_HEIGHT) / 2.0),
        }
    }

    // split quad into 2 triangles and fill
    color := face_colors[i % 6]
    fill_triangle(app, screen_verts[0], screen_verts[1], screen_verts[2], color)
    fill_triangle(app, screen_verts[0], screen_verts[2], screen_verts[3], color)
    }
}

plot_pixel :: proc(app: ^App, x, y: i32, color: u32) {
    draw_pixel(app, int(x), int(y), color)
}

draw_line_between_points :: proc(app: ^App, x0, y0, x1, y1: i32, color: u32) {
    x0 := x0
    y0 := y0

    dx := abs(x1 - x0)
    dy := abs(y1 - y0)

    sx := x0 < x1 ? 1 : -1
    sy := y0 < y1 ? 1 : -1

    err := dx - dy

    for {
        plot_pixel(app, x0, y0, color)
 
        if x0 == x1 && y0 == y1 { 
            break
        }

        e2 := 2 * err
        if e2 > -dy {
            err -= dy
            x0 += i32(sx)
        }
        if e2 < dx {
            err += dx
            y0 += i32(sy)
        }
    }
}

matrix_multiply :: proc(a: Mat4, b: Mat4) -> Mat4 {
    c: Mat4

    for i in 0..<4 {
        for j in 0..<4 {
            for k in 0..<4 {
                c[i][j] += a[i][k] * b[k][j]
            }
        }
    }
    return c
}

main_loop :: proc(app: ^App) {
    for {
        for SDL.PollEvent(&app.event) {
            #partial switch app.event.type {
                case .QUIT:
                    return
            }
        }

        // SDL.SetRenderDrawColor(app.renderer, 0, 0, 0, 255)
        // SDL.RenderClear(app.renderer)

        for i in 0..<SCREEN_WIDTH * SCREEN_HEIGHT {
            app.pixels[i] = 0x000000FF
        }

        app.angle_x += 0.3
        app.angle_y += 0.5
        app.angle_z += 0.2
        project_and_draw(app, app.angle_x, app.angle_y, app.angle_z)
        
        // Upload pixel array to GPU texture
        SDL.UpdateTexture(app.pixel, nil, &app.pixels[0], SCREEN_WIDTH * 4)
        // Draw texture to the screen
        SDL.RenderTexture(app.renderer, app.pixel, nil, nil)

        SDL.RenderPresent(app.renderer)
        SDL.Delay(16)
    }
}

main :: proc() {
    fmt.printf("hello world")

    app := new(App)
    defer free(app)

    if !initialize(app) do return
    main_loop(app)

    TTF.CloseFont(app.font)
    TTF.Quit()
    SDL.DestroyWindow(app.window)
    SDL.DestroyRenderer(app.renderer)
    SDL.Quit()
}