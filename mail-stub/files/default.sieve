require ["fileinto"];

if allof (header :contains "X-Spam-Flag" "YES")
{
	  fileinto "INBOX.Junk";
}
