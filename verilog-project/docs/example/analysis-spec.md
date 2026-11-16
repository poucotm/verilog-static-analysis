<!-- 작성 안내 (유저용. 분석 내용이 아니므로 Claude는 이 주석을 무시한다)
- 이 파일을 docs/analysis-spec.md 로 복사해 고쳐 쓴다.
- 모든 절을 채울 필요는 없다. 필요 없는 절과 항목은 지운다.
- 인터페이스 규격만 간단히 적어도 된다.
- 한 줄에 하나씩 "- " 로 적는다. C1, I1, R1 같은 ID는 붙여도 되고 빼도 된다.
- 이 주석은 지워도 되고 남겨 둬도 된다.
-->

# 분석 스펙

## 입력 조건
- start 는 1클럭 pulse 이고, 연속 2클럭 이상 1이 되지 않는다
- start 는 이전 작업의 done 이 나온 뒤에만 다시 온다
- s_axis (tvalid / tready / tdata[63:0] / tkeep[7:0] / tlast) 는 AXI4-Stream 규칙을 지킨다. tvalid 가 1이 되면 tready 를 받을 때까지 값을 유지한다
- s_axis_tkeep 은 tlast=0 인 beat 에서 항상 8'hFF 이다. 부분 유효 바이트는 마지막 beat 에만 온다
- cfg_len 은 start 전에 설정되고, 작업 중에는 바뀌지 않는다 (범위 1 ~ 1024)
- srst 는 작업 중에도 올 수 있다

## 출력 조건
- m_axis (tvalid / tready / tdata[63:0] / tlast) 는 AXI4-Stream 규칙을 지켜야 한다
- 받는 쪽은 m_axis_tready 를 최대 16클럭까지 0 으로 둘 수 있다
- done 은 마지막 출력 beat 가 나간 다음 클럭에 1클럭 pulse 로 낸다

## 의도된 동작
- srst 가 오면 처리 중이던 프레임은 버린다 (남은 출력 beat 를 내지 않는다)

## 성능 목표
- 처리율: 입력 1 beat 당 1클럭 (back-to-back 입력을 멈추지 않고 처리)

## 전력 목표
- 합성 도구가 enable 에서 클럭 게이팅을 자동으로 넣는다

## 요청 사항
- 마지막 beat 의 tkeep 이 부분 유효 (예: 8'h0F) 일 때 출력 데이터 바이트 정렬이 맞는지 확인
- m_axis_tready 가 오래 0 일 때 입력 데이터가 유실되거나 중복되는지 확인
- 작업 중 srst 가 오면 다음 start 부터 정상 동작하는지 확인
