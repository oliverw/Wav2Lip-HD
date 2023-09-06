param (
  [Parameter(Position = 0)]
  [string]$video,

  [Parameter(Position = 1)]
  [string]$audio,

  [switch]$clean
)

& (Join-Path $env:USERPROFILE "anaconda3" "shell" "condabin" "conda-hook.ps1")

$input_video = Join-Path "input_videos" $video
$input_audio = Join-Path "input_audios" $audio
$input_video_item = (Get-Item $input_video)

# check if input_video is not a video
$input_ext = $input_video_item.Extension.ToLower()

if (($input_ext -eq ".jpg") -or ($input_ext -eq ".png")) {
  # convert to 60sec video
  $new_input_video = Join-Path $input_video_item.Directory ("{0}.{1}" -f $input_video_item.BaseName, "mp4")
  ffmpeg -hide_banner -loglevel error -loop 1 -f image2 -i $input_video -r 24 -c:v h264_nvenc -tune:v hq -rc:v vbr -cq:v 19 -b:v 0 -profile:v high -t 60 $new_input_video

  # update vars
  $input_video = $new_input_video
  $input_video_item = (Get-Item $input_video)
}

$title = $input_video_item.BaseName
$frames_wav2lip = "frames_wav2lip"
$output_videos_wav2lip = "output_videos_wav2lip"
$frames_path = Join-Path $frames_wav2lip $title
$frames_path_upscaled = Join-Path $frames_wav2lip "upscaled" $title

# activate conda env
conda activate wav2lip-hd

$outfile = Join-Path $output_videos_wav2lip "$title.mp4"

if ((-not (Test-Path $outfile)) -or $clean) {
  Write-Host "Lip syncing .."

  python inference.py --checkpoint_path "checkpoints/wav2lip_gan.pth" --segmentation_path "checkpoints/face_segmentation.pth" --sr_path "checkpoints/esrgan_yunying.pth" --face $input_video --audio $input_audio --save_frames --gt_path "data/gt" --pred_path "data/lq" --no_sr --no_segmentation --outfile $outfile
  
  Write-Host "Splitting video into frames ..."
  python video2frames.py --input_video (Join-Path $output_videos_wav2lip "$title.mp4") --frames_path $frames_path
}

if ((Test-Path $frames_path_upscaled) -and $clean) {
  Remove-Item -Path $frames_path_upscaled -Recurse -Force | Out-Null
}

if (-not (Test-Path $frames_path_upscaled)) {
  New-Item -Path $frames_path_upscaled -ItemType Directory | Out-Null
}

Push-Location Real-ESRGAN

try {
  conda activate Real-ESRGAN

  Write-Host "Upscaling .."
  python inference_realesrgan.py -n RealESRGAN_x4plus --face_enhance --outscale 2 -i (Join-Path ".." $frames_path) -o (Join-Path ".." $frames_path_upscaled)

  Write-Host "Combining frames and audio into final video .."
  $result_path = (Join-Path ".." results "$title.mp4")
  ffmpeg -hide_banner -loglevel error -y -r 30 -i (Join-Path ".." $frames_path_upscaled frame_%05d_out.jpg) -i (Join-Path ".." $input_audio) -c:v h264_nvenc -tune:v hq -rc:v vbr -cq:v 19 -b:v 0 -profile:v high -c:a aac -b:a 128k $result_path

  ffplay -autoexit $result_path
}

finally {
  Pop-Location

  conda activate wav2lip-hd
}
