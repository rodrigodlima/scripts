#!/usr/bin/env python3.10
import sys
import os
import yt_dlp
import whisper

def download_audio(video_url, output_filename="audio.mp3"):
    """
    Faz o download do áudio do vídeo usando yt-dlp e salva como MP3.
    """
    ydl_opts = {
        'format': 'bestaudio/best',
        'outtmpl': output_filename.replace('.mp3', '') + '.%(ext)s',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '192',
        }],
        'quiet': True,
    }

    print(f"🎬 Baixando áudio de: {video_url}")
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([video_url])

    mp3_file = output_filename
    if not os.path.exists(mp3_file):
        # tenta encontrar o arquivo convertido
        for f in os.listdir('.'):
            if f.endswith('.mp3'):
                mp3_file = f
                break
    print(f"✅ Áudio salvo em: {mp3_file}")
    return mp3_file


def transcribe_audio(audio_path, model_name="small"):
    """
    Transcreve o áudio usando o modelo Whisper.
    """
    print(f"🧠 Carregando modelo Whisper ({model_name})...")
    model = whisper.load_model(model_name)
    print("🔊 Transcrevendo áudio...")
    result = model.transcribe(audio_path, verbose=True)
    return result


def save_srt(result, filename="legenda.srt"):
    """
    Salva o resultado da transcrição em formato .srt.
    """
    def fmt_time(t):
        h = int(t // 3600)
        m = int((t % 3600) // 60)
        s = int(t % 60)
        ms = int((t * 1000) % 1000)
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

    print(f"📝 Salvando legenda em: {filename}")
    with open(filename, "w", encoding="utf-8") as f:
        for i, segment in enumerate(result["segments"], start=1):
            f.write(f"{i}\n{fmt_time(segment['start'])} --> {fmt_time(segment['end'])}\n{segment['text'].strip()}\n\n")

    print("✅ Legenda gerada com sucesso!")


def main():
    if len(sys.argv) < 2:
        print("Uso: python whisper_subs.py <url_do_video> [modelo]")
        print("Exemplo: python whisper_subs.py https://www.youtube.com/watch?v=abcd1234 base")
        sys.exit(1)

    video_url = sys.argv[1]
    model_name = sys.argv[2] if len(sys.argv) > 2 else "small"

    audio_path = download_audio(video_url)
    result = transcribe_audio(audio_path, model_name)
    save_srt(result)

    print("\n🎉 Finalizado! Arquivo de legenda salvo em 'legenda.srt'.")


if __name__ == "__main__":
    main()

