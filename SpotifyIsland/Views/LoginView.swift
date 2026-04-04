import SwiftUI

struct LoginView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 6) {
                Text("Connect to Spotify")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("Control your music from the notch")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button(action: onLogin) {
                Text("Login with Spotify")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.11, green: 0.73, blue: 0.33)) // #1DB954
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
