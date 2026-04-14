import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { name, targetInfo, benefitInfo, rawContent } = await req.json()

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY')
    if (!geminiApiKey) throw new Error('GEMINI_API_KEY 없음')

    const sections = [
      rawContent ? `원문:\n${rawContent.slice(0, 2000)}` : '',
      targetInfo ? `지원 대상: ${targetInfo}` : '',
      benefitInfo ? `지원 혜택: ${benefitInfo}` : '',
    ].filter(Boolean).join('\n')

    const prompt = `당신은 복지 서비스 전문가입니다.
아래 복지 서비스를 노인 부모님을 모시는 자녀가 바로 이해할 수 있도록 2~3문장으로 요약해주세요.
- 누가 신청 가능한지
- 어떤 혜택을 받는지
- 신청 방법이나 연락처(있으면)
- 전문용어 없이 쉬운 말로

서비스명: ${name}
${sections}

요약 (한국어, 3문장 이내):`.trim()

    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiApiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.3, maxOutputTokens: 300 },
        }),
      }
    )

    const data = await res.json()
    const summary = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? ''

    return new Response(JSON.stringify({ summary }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
