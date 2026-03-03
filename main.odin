package main

import "core:fmt"
import "core:log"
import "core:math"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

App :: struct {
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    event: SDL.Event,

    font: ^TTF.Font,
    pixel: ^SDL.Texture,
    pixels: [SCREEN_WIDTH * SCREEN_HEIGHT]u32,
    angle: f32
}

SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 560

FONT_SIZE :: 40

Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: [4][4]f32

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

project_and_draw :: proc(app: ^App, angle: f32) {
    screen_x1: i32
    screen_y1: i32
    screen_x2: i32
    screen_y2: i32
    per := perspective_matrix(75.0, f32(SCREEN_WIDTH) / f32(SCREEN_HEIGHT), 0.1, 100.0)
    rot := rotation_matrix_around_y_axis(angle)

    for edge in cube_edges {
        vertex_1 := cube_vertices[edge[0]]
        vertex_2 := cube_vertices[edge[1]]

        // apply rotation
        v1 := transform_vertex(vertex_1, rot)
        v2 := transform_vertex(vertex_2, rot)
        
        // move cube back so its in view
        v1[2] += 3.0
        v2[2] += 3.0

        // convert to Vec4 with w = 1.0
        v1_4 := Vec4{v1[0], v1[1], v1[2], 1.0}
        v2_4 := Vec4{v2[0], v2[1], v2[2], 1.0}

        // apply perspective matrix
        p1 := transform_vertex_4(v1_4, per)
        p2 := transform_vertex_4(v2_4, per)

        // perspective divide
        p1_x := p1[0] / p1[3]
        p1_y := p1[1] / p1[3]
        p2_x := p2[0] / p2[3]
        p2_y := p2[1] / p2[3]

        // convert from -1..1 range to screen coordinates
        screen_x1 = i32((p1_x + 1.0) * f32(SCREEN_WIDTH) / 2.0)
        screen_y1 = i32((1.0 - p1_y) * f32(SCREEN_HEIGHT) / 2.0)
        screen_x2 = i32((p2_x + 1.0) * f32(SCREEN_WIDTH) / 2.0)
        screen_y2 = i32((1.0 - p2_y) * f32(SCREEN_HEIGHT) / 2.0)

        draw_line_between_points(app, screen_x1, screen_y1, screen_x2, screen_y2, 0xFFFFFFFF)
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

        app.angle += 0.5
        project_and_draw(app, app.angle)
        
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