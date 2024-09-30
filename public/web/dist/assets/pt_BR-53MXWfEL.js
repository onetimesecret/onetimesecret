const e={COMMON:{broadcast:"",description:"Mantenha dados sensíveis fora de seus emails ou logs de conversa. Compartilhe um link secreto que fica disponível somente uma vez.",keywords:"segredo,gerador de senha,compartilhar um segredo,único",button_create_secret:"Criar link secreto",button_generate_secret:"Ou gerar uma senha aleatória",secret_privacy_options:"Opções de Privacidade",secret_passphrase:"Senha mestre",secret_passphrase_hint:"Uma palavra ou frase que seja difícil de adivinhar",secret_recipient_address:"Endereço do Destinatário",secret_placeholder:"Conteúdo do segredo deve vir aqui...",header_create_account:"Criar Conta",header_about:"Sobre",header_sign_in:"Entrar",header_dashboard:"Conta",header_logout:"Sair",secret:"Segredo",received:"Recebido",burned:"Removido",expires_in:"Expira em",burn_this_secret:"Remover este segredo",burn_this_secret_hint:"Remover um segredo irá apagá-lo antes de ser lido (clique para confirmar)",burn_this_secret_confirm_hint:"Remover um segredo é permanente e não pode ser desfeito",msg_check_email:"Verifique seu email",click_to_continue:"Clique para continuar →",click_to_verify:"Continue para verificar sua conta:",error_secret:"Você não forneceu nada para compartilhar",error_passphrase:"Verifique a senha mestre",enter_passphrase_here:"Entre a senha mestre aqui",view_secret:"Ver segredo",careful_only_see_once:"cuidado: só será mostrado uma vez.",warning:"Atenção",oops:"Oops!",error:"Erro",secret_was_truncated:"A mensagem foi cortada porque tinha mais de",signup_for_more:"Cadastre-se para usar mais",login_to_your_account:"Entrar na sua conta",sent_to:"Enviar para: ",field_email:"Email",field_password:"Senha",field_password2:"Confirmar Senha",button_create_account:"Criar Conta",share_a_secret:"Compartilhar um segredo",title_home:"Home",title_recent_secrets:"Segredos Recentes",word_none:"Nenhum",word_burned:"removido",word_received:"recebido",word_confirm:"Confirmar",word_cancel:"Cancelar",feedback_text:"Tem uma pergunta ou comentário?",button_send_feedback:"Enviar Feedback",verification_sent_to:"Uma verificação foi enviada para"},homepage:{tagline1:"Cole uma senha, mensagem secreta ou link privado abaixo.",tagline2:"Mantenha dados sensíveis fora de seus emails ou logs de conversa.",secret_hint:"* Um link secreto funciona apenas uma vez e depois desaparece para sempre.",secret_form_more_text1:"Cadastre-se para uma",secret_form_more_text2:"conta gratuita",secret_form_more_text3:"e seja capaz de enviar um segredo por email.",cta_title:"Use um domínio personalizado",cta_subtitle:"Eleve sua marca e compartilhe com confiança",cta_feature1:"Seu próprio domínio personalizado",cta_feature2:"Compartilhamento ilimitado de segredos",cta_feature3:"Controles avançados de privacidade",explore_premium_plans:"Explore os planos Premium",need_free_account:"Está apenas começando?",sign_up_free:"Crie uma conta gratuita"},private:{pretext:"Compartilhar este link:",requires_passphrase:"Requerir uma senha mestre.",this_msg_is_encrypted:"Esta mensagem será criptografada com sua senha mestre.",only_see_once:"você só verá isso uma vez"},shared:{requires_passphrase:"Esta mensagem requere uma senha mestre:",viewed_own_secret:"Você viu seu próprio segredo. Este não está mais disponível para ninguém.",you_created_this_secret:"Você criou este segredo. Se você o ver, o destinatário não será capaz de vê-lo.",your_secret_message:"Sua mensagem secreta:",this_message_for_you:"Esta mensagem é para você:",reply_with_secret:"Responder com outro segredo"},dashboard:{title_received:"Recebido",title_not_received:"Não Recebido",title_no_recent_secrets:"Nenhum segredo recente"},login:{need_an_account:"Precisa de uma conta?",forgot_your_password:"Esqueceu sua senha?",button_sign_in:"Entrar",enter_your_credentials:"Entre com suas credenciais"},incoming:{tagline1:"Cole uma senha, mensagem secreta ou link privado abaixo.",tagline2:"Mantenha dados sensíveis fora de seus emails ou logs de conversa.",secret_hint:"* Um link secreto funciona apenas uma vez e depois desaparece para sempre.",incoming_button_create:"Enviar para Equipe de Suporte Send to Support Staff",incoming_secret_options:"Informações para Suporte",incoming_secret_placeholder:"Entre com qualquer informação que seu representante de suporte vai precisar (ex. senha do sistema)",incoming_ticket_number:"Entre com número do ticket #",incoming_ticket_number_hint:"Você pode encontrar este número no seu email (ex. 123456)",incoming_recipient_address:"Destinatário de Suporte",incoming_success_message:"Seu email foi enviado"}},a={incomingsupport:{subject:"[Ticket: %s]",body1:"Um cliente te enviou a seguinte informação"},secretlink:{subject:"%s te enviou um segredo",body1:"Temos um segredo para você de",body_tagline:"Se você não conhece o remetente ou acredita ser spam, envie-nos os detalhes aqui:"},welcome:{subject:"Verifique sua conta Onetime Secret",body1:"Bem-vindo(a) ao Onetime Secret. Temos um segredo para você!",please_verify:"Por favor, verifique sua conta:",postscript1:"Este email foi enviado para",postscript2:"Se você não criou esta conta, apague esta mensagem e nós não iremos lhe contatar novamente."}},r={web:e,email:a};export{r as default,a as email,e as web};