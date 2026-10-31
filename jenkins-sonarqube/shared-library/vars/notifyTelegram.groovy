// One Telegram message per build result. Never fails the build: a notification
// that cannot be sent is logged and dropped.
//
// The credential is a username/password pair — username = chat id,
// password = bot token — created by init.groovy.d/10-credentials.groovy.

def call(String status, String emoji, String detail = '') {
  try {
    String text = "${emoji} ${env.JOB_NAME} #${env.BUILD_NUMBER} ${status}\n" +
                  (detail ? "${detail}\n" : '') +
                  "${env.BUILD_URL}"
    withCredentials([usernamePassword(credentialsId: 'telegram-notify',
                                      usernameVariable: 'TG_CHAT_ID',
                                      passwordVariable: 'TG_TOKEN')]) {
      withEnv(["TG_TEXT=${text}"]) {
        sh '''
          set +x
          curl -fsS --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=${TG_TEXT}" > /dev/null
        '''
      }
    }
  } catch (err) {
    echo "Telegram notification failed (build unaffected): ${err}"
  }
}
