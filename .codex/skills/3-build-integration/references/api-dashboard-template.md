
## 📊 **버전 히스토리**

| 버전     | 📅 작성일     | 🔄 주요 변경사항          | 👤 작성자 |
| ------ | ---------- | ------------------- | ------ |
| v{VERSION} | {YYYY-MM-DD} | {변경사항 설명} | {작성자}    |

---

## 🎯 **API 개요**

### **📌 목적**
{프로젝트명} 시스템의 **{핵심 기능 설명}**을 위한 RESTful API 제공

### **🔗 Base URL**
```bash
# 개발 환경
{DEV_BASE_URL}

# 운영 환경  
{PROD_BASE_URL}
```

---

## 📚 **API 카테고리별 명세서**

> 프로젝트의 API 카테고리별로 아래 블록을 반복한다.
> `{category_key}`와 `dv.pages()` 경로를 실제 프로젝트에 맞게 수정할 것.

### **📊 {카테고리명}**
- **{기능 설명 1}**
- **{기능 설명 2}**
- **{기능 설명 3}**

```dataviewjs
let pages = dv.pages('"6. API 명세서/v{VERSION}/apis"').where(p => p.category == "{category_key}");
if (pages.length === 0) {
    dv.paragraph("⚠️ apis/ 디렉토리에 {category_key} 카테고리 API 파일이 없습니다.");
} else {
    dv.table(
        ["✅ 완료", "🌐 엔드포인트", "📡 메소드", "📝 설명", "📤 Request", "📥 Response", "🎯 우선순위"],
        pages.map(p => [
            p.completed ? "✅" : "❌",
            `[[${p.file.name}|${p.endpoint || "N/A"}]]`,
            p.http_method ? p.http_method.toUpperCase() : "N/A",
            p.description || "N/A",
            Array.isArray(p.request) ? p.request.join(", ") : (p.request || "N/A"),
            Array.isArray(p.response) ? p.response.join(", ") : (p.response || "N/A"),
            p.requirement_priority || "medium"
        ])
    );
}
```

<!-- 카테고리가 여러 개이면 위 블록을 복제하여 category_key를 변경한다 -->

---

## 📋 **HTTP 상태 코드 정의**

| 코드 | 의미 | 사용 시나리오 |
|------|------|---------------|
| **200** | OK | 요청 성공 (조회, 업데이트) |
| **201** | Created | 리소스 생성 성공 |
| **202** | Accepted | 비동기 작업 수락 |
| **204** | No Content | 삭제 성공 |
| **400** | Bad Request | 잘못된 요청 파라미터 |
| **401** | Unauthorized | 인증 실패 |
| **403** | Forbidden | 권한 없음 |
| **404** | Not Found | 리소스 없음 |
| **409** | Conflict | 리소스 충돌 |
| **422** | Unprocessable Entity | 데이터 검증 실패 |
| **429** | Too Many Requests | 요청 제한 초과 |
| **500** | Internal Server Error | 서버 내부 오류 |

---

## 📊 **API 개발 진행률**

### **🎯 전체 진행 현황**
```dataviewjs
let pages = dv.pages('"6. API 명세서/v{VERSION}/apis"');

let totalApis = 0;
let completedApis = 0;
let categoryStats = {};

for (let page of pages) {
    totalApis++;
    if (page.completed) completedApis++;
    
    const category = page.category || "미분류";
    if (!categoryStats[category]) {
        categoryStats[category] = { total: 0, completed: 0 };
    }
    categoryStats[category].total++;
    if (page.completed) categoryStats[category].completed++;
}

for (let category in categoryStats) {
    const stats = categoryStats[category];
    stats.percentage = stats.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0;
}

const overallPercentage = totalApis > 0 ? Math.round((completedApis / totalApis) * 100) : 0;

// ⬇️ 프로젝트에 맞게 카테고리 한글명을 정의한다
const categoryNames = {
    // "auth": "🔐 인증",
    // "users": "👤 사용자",
    // "orders": "📦 주문",
};

let tableData = [];
for (let [category, stats] of Object.entries(categoryStats)) {
    const displayName = categoryNames[category] || `📁 ${category}`;
    tableData.push([
        displayName,
        `📊 ${stats.total}`,
        `✅ ${stats.completed}`,
        `📈 ${stats.percentage}%`
    ]);
}

tableData.push([
    "**🎯 전체**",
    `**📊 ${totalApis}**`,
    `**✅ ${completedApis}**`,
    `**📈 ${overallPercentage}%**`
]);

if (totalApis === 0) {
    dv.paragraph("⚠️ apis/ 디렉토리에 API 명세서 파일이 없습니다.");
} else {
    dv.table(
        ["📁 카테고리", "📊 총 API 수", "✅ 완료", "📈 진행률"],
        tableData
    );
}
```

---

## 🔍 **전체 API 엔드포인트 목록**

### **📋 모든 API 통합 보기**
```dataviewjs
let pages = dv.pages('"6. API 명세서/v{VERSION}/apis"');

// ⬇️ 프로젝트에 맞게 카테고리 한글명을 정의한다 (진행률 섹션과 동일하게 유지)
const categoryNames = {
    // "auth": "🔐 인증",
    // "users": "👤 사용자",
    // "orders": "📦 주문",
};

const priorityOrder = { "high": 1, "medium": 2, "low": 3 };

if (pages.length === 0) {
    dv.paragraph("⚠️ apis/ 디렉토리에 API 명세서 파일이 없습니다.");
} else {
    let allApis = pages.map(p => [
        categoryNames[p.category] || p.category || "미분류",
        p.completed ? "✅" : "❌",
        `[[${p.file.name}|${p.endpoint || "N/A"}]]`,
        p.http_method ? p.http_method.toUpperCase() : "N/A",
        p.description || "N/A",
        p.requirement_priority || "medium"
    ]);

    allApis.sort((a, b) => {
        if (a[0] !== b[0]) return a[0].localeCompare(b[0]);
        if (a[1] !== b[1]) return a[1] === "✅" ? 1 : -1;
        const priorityA = priorityOrder[a[5]] || 2;
        const priorityB = priorityOrder[b[5]] || 2;
        return priorityA - priorityB;
    });

    dv.table(
        ["📁 카테고리", "✅ 상태", "🌐 Endpoint", "📡 Method", "📝 Description", "🎯 Priority"],
        allApis
    );
}
```

---

## 🔍 **API 테스트 가이드**

### **🧪 테스트 환경 설정**
```bash
export API_BASE_URL="{DEV_BASE_URL}"

curl -H "Content-Type: application/json" $API_BASE_URL/health
```

### **📋 테스트 체크리스트**
- [ ] **에러 응답 형식** 일관성 체크
- [ ] **성능 임계값** 만족 여부 확인

---

## 📚 **참고 자료 및 도구**

### **🔧 개발 도구**
- **📝 API 문서**: [Swagger UI]({DEV_BASE_URL}/docs)

### **📖 외부 참조**
- **🌐 RESTful API 가이드**: [REST API Best Practices](https://restfulapi.net/)
- **📋 HTTP 상태 코드**: [MDN HTTP Status](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status)

---

*📅 마지막 업데이트: {YYYY-MM-DD} | 👤 담당자: {담당자}*
