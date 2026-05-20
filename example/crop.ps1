Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('art\a\gfx\NPC_test.png')
$w = [Math]::Floor($img.Width / 8)
$h = [Math]::Floor($img.Height / 8)
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$rectDest = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$rectSrc = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$g.DrawImage($img, $rectDest, $rectSrc, [System.Drawing.GraphicsUnit]::Pixel)
$bmp.Save('art\characters\villager.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
$img.Dispose()
echo 'Successfully cropped villager.png'
