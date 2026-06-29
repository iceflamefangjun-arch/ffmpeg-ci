1. bee_env_init接口传入参数格式（json）及参数描述如下：
{
	uid: "xxx", // 离线DRM请求中使用，用于解密缓存在本地的离线DRM视频，下载离线DRM视频时使用的uid必须与解密时一致

	/* 以下参数设置全局变量，对应bee_open/bee_open_async中的同名参数。
	   1. 如果设置了全局参数，而bee_open/bee_open_async中没有设置，全局参数会作为默认值启用。
	   2. 如果设置了bee_open/bee_open_async的参数，则会覆盖全局参数（如果同时也设置了对应的全局参数）。
	*/
	dns_server: 8.8.8.8,
	doh_url: "https://doh1.sohu.com/dns-query",
	tcp_fastopen: true,
	proxy: "http://127.0.0.1:8888",
	proxy_user: "xxx",
	proxy_pass: "xxx",
}

2. bee_open/bee_open_async接口传入参数格式（json）及参数描述如下：
{
	dns_server: "8.8.8.8,1.1.1.1,...",           // 设置dns解析服务器地址，可以指定多个，以逗号分割
	doh_url: "https://doh1.sohu.com/dns-query",  // 设置doh(dns over http)的url

	connect_timeout: 3,    // 设置连接超时x秒，默认3秒，不用担心太短，会有重试，除非网络质量太差可以调大
	timeout: 10,           // 设置整个http下载用时上限（包括连接用时），超过时间下载会失败，一般不用设置

	tcp_fastopen: true,    // 如果确定系统支持TCP fastopen的话可以设置成true，否则无效

	http3: true,           // 如果确定服务器支持HTTP3协议，可以强制走HTTP3协议，省去通过协商过程。如果服务器不支持，也会自动回退，不会导致请求出错

	speed_max: 1000000,    // 最大下载速度，达到即限速
	speed_min: 1,          // 最小下载速度，5秒内下载平均速度低于该值失败，可用于快速检测网络断开

	verbose: true,         // 日志中输出http连接的详细信息，一般不用设置，第一次重试时，该选项会自动打开

	redirect: 0,           // 对于3xx的返回，默认会自动跳转（最多5次），设置成0表示不自动跳转，一般为了拿到location才设置成0

	/* 下面四个参数用于设置网络代理。
	   1. 支持http/https/socks4/socks4a/socks5/socks5h。
	   2. 使用方法参照sync_test.cpp的test15，test16。
	*/
	proxy: "http://127.0.0.1:8888",
	proxy_user: "xxx",
	proxy_pass: "xxx",     // proxy_user和proxy_pass可以直接合并到proxy中，http://user:pass@proxy.server.com:8888。
	untrust_proxy: true,   // 代理服务器为https协议时不校验证书合法性

	custom_headers: ["User-Agent: xxxx", "X-Content-Type: json", ...], // 自定义http头

	/* 下面两个参数控制用分块或非分块下载，使用方法参照sync_test.cpp的test1，test2，test3，test4。
	   1. 大部分情况下分块下载逻辑更合适，网络rtt较大，但丢包很少的情况下非分块下载由于有更大的发送窗口，因而效率更高。
	   2. 两种下载逻辑都支持seek。
	*/
	player: "SOHUPLAYER",
	chunked: 0,

	/* HTTP POST */
	post: "xxx",           // post一条字符串消息
	form: {                // post一个表单，表单格式为包含1个或多个键值对的json对象
		"text": "this is a simple message",         // 键（text）可以为任意不以@开头的字符串
		"@file": "/data/abc.txt",                   // 键(@file)可以为任意以@开头的字符串，告诉服务器其对应内容的文件名file，值部分为要上传内容的本地文件的路径
		"+@msg": "this is another simple message",  // 以@开头的字符串作为键值，但不希望被解释成文件名，需要在前面加上+
		...
	},

	...
}
