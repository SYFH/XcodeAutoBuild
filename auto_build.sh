#!/bin/sh

# 获取项目所在目录
cd "$1"
script_dir="$( cd "$( dirname "$0"  )" && pwd  )"

# 指定要打包编译的方式 : Release,Debug。一般用Release。必填
build_configuration="Release"

# 是否上传 dSYM 到 Bugly
is_upload_dSYM_Bugly="false"

# Bugly
bugly_app_key=""
bugly_app_id=""

# App Store
apple_id=""
apple_id_password=""

# 递归遍历
traverse_dir() {
    suffix=$1
    dir=$2
    
    for file in `ls -a $dir`
    do
        if [ -d ${dir}/$file ]
        then
            if [[ $file != '.' && $file != '..' ]]
            then
                # 递归
                traverse_dir $suffix ${dir}/$file
            fi
        else
            # 调用查找指定后缀文件
            filepath=${dir}/$file
            if [ "${filepath##*.}"x = "$suffix"x ];then
                filename=$(basename $filepath)
                filename="${filename%.*}"
                echo -e $filename
            fi
        fi
    done
}

# Xcode 路径
xcode_paths=()
get_xcode_path() {
    dir="/Applications"
    prefix="Xcode"

    for file in `ls -a $dir`
    do
        # 查找 Xcode 开头 app 结尾
        filepath=${dir}/$file
        if [[ "${filepath##*.}"x = "app"x && $file == $prefix* ]]; then
            xcode_paths[${#xcode_paths[*]}]=$filepath
        fi
    done
}



# 安装前置应用
install_pre() {
    pre_name=$1
    xcpretty_exist=`gem list $pre_name | grep $pre_name`
    if [[ ${#xcpretty_exist} == 0 || $xcpretty_exist != "$pre_name ("* ]]; then
        echo -e "\033[33;1m未安装 $pre_name, 将自动安装\033[0m"
        sudo gem install $pre_name
        echo -e "\033[33;1m安装 $pre_name 成功 \033[0m"
        echo -e ""
    else
        echo -e "\033[33;1m已安装 $pre_name \033[0m"
    fi
}

# 清除文件
clean_temp() {
    rm -f "export_path"
}


# ===================================
# 检查前置应用安装
echo -e "\033[32;1m检查前置应用安装... \033[0m"
install_pre "xcpretty"
install_pre "xcpretty-travis-formatter"


echo -e "\033[32;1m获取项目设置信息... \033[0m"
# .xcworkspace的名字
workspace_name=`traverse_dir xcworkspace "$script_dir"`
if [[ `expr ${#workspace_name}` == 0 ]]; then
    echo -e "\033[31;1m未找到 xcworkspace 文件\033[0m"
    clean_temp
    exit 1
fi

# ===================================
# 获取项目设置信息 
info=`xcodebuild -showBuildSettings`
workspage_bundle_id=`echo -e "$info" | grep PRODUCT_BUNDLE_IDENTIFIER | awk -F ' = ' '{print $2}'`
workspage_team_id=`echo -e "$info" | grep DEVELOPMENT_TEAM | awk -F ' = ' '{print $2}'`
scheme_name=`echo -e "$info" | grep TARGET_NAME | awk -F ' = ' '{print $2}'`
echo -e "\033[33;1mBundle ID: $workspage_bundle_id"
echo -e "Team ID: $workspage_team_id"
echo -e "Scheme Name: $scheme_name \033[0m"

# ===================================
# 设置指定Xcode
get_xcode_path

echo -e "\033[32;1m设置指定Xcode...\033[0m"

if [[ `expr ${#xcode_paths[@]}` == 1 ]]; then
    number=0
else
    echo -e "\033[33;1m请输入数字选择指定的 Xcode\033[0m"
    for i in "${!xcode_paths[@]}";   
    do
        echo -e "${i}: ${xcode_paths[$i]}"
    done
    read number
fi

length=`expr ${#xcode_paths[*]} - 1`
if [[ $number > $length || $number < 0 ]]; then
    echo -e "\033[31;1m错误的编号, 将使用默认路径: `xcode-select -p`\033[0m"
    number=0
fi

selected_xcode_path="${xcode_paths[$number]}"
echo -e "\033[33;1m输入密码以设置 Xcode"
sudo xcode-select -s "$selected_xcode_path/Contents/Developer"
echo -e "已设置为指定 Xcode: `xcode-select -p`\033[0m"

# ===================================
# 设置基本信息
echo -e "\033[32;1m设置基本信息...\033[0m"
# method，打包的方式。方式分别为 development, ad-hoc, app-store, enterprise 。必填
echo -e "请输入打包方式编号 \033[33;1m [1:app-store 2:ad-hoc 3:development 4:enterprise]\033[0m"

read number
while([[ $number != 1 ]] && [[ $number != 2 ]] && [[ $number != 3 ]] && [[ $number != 4 ]])
do
echo -e "请输入打包方式编号 \033[33;1m [1:app-store 2:ad-hoc 3:development 4:enterprise]\033[0m"
read number
done

if [ $number == 1 ];then
method="app-store"
fi

if [ $number == 2 ];then
method="ad-hoc"
fi

if [ $number == 3 ];then
method="development"
fi

if [ $number == 4 ];then
method="development"
fi


# 下面两个参数只是在手动指定Pofile文件的时候用到，如果使用Xcode自动管理Profile,直接留空就好
# (跟method对应的)mobileprovision文件名，需要先双击安装.mobileprovision文件.手动管理Profile时必填
mobileprovision_name=""

# 项目的bundleID
bundle_identifier=$workspage_bundle_id

# ===================================
# 设置基本参数

echo -e "\033[32;1m脚本配置参数检查...\033[0m"
echo -e "\033[33;1mworkspace_name            =${workspace_name}"
echo -e "project_name              =${project_name}"
echo -e "scheme_name               =${scheme_name}"
echo -e "build_configuration       =${build_configuration}"
echo -e "bundle_identifier         =${bundle_identifier}"
echo -e "method                    =${method}"
echo -e "mobileprovision_name      =${mobileprovision_name} \033[0m"


# ===================================
# 检查固定参数

# 工程根目录
project_dir="$script_dir"

# 时间
DATE=`date '+%Y%m%d_%H%M%S'`
# 指定输出导出文件夹路径
export_path="$project_dir/Package/$scheme_name-$DATE"
# 指定输出归档文件路径
export_archive_path="$export_path/$scheme_name.xcarchive"
# 指定输出ipa文件夹路径
export_ipa_path="$export_path"
# 指定输出ipa名称
ipa_name="${scheme_name}_${DATE}"
# 指定导出ipa包需要用到的plist配置文件的路径
export_options_plist_path="$project_dir/ExportOptions.plist"

dSYM_path="$export_archive_path/dSYMs/$scheme_name.app.dSYM"
new_dSYM_path="$export_path/$scheme_name.app.dSYM"
zip_dSYM_path="$export_path/$scheme_name.app.dSYM.zip"

echo -e "\033[32;1m脚本固定参数检查...\033[0m"
echo -e "\033[33;1mproject_dir               =${project_dir}"
echo -e "DATE                      =${DATE}"
echo -e "export_path               =${export_path}"
echo -e "export_archive_path       =${export_archive_path}"
echo -e "export_ipa_path           =${export_ipa_path}"
echo -e "export_options_plist_path =${export_options_plist_path}"
echo -e "ipa_name                  =${ipa_name}"
echo -e "zip_dSYM_path             =${zip_dSYM_path} \033[0m"


# ===================================
# 自动打包

echo -e "\033[32m开始构建项目...\033[0m"
# 进入项目工程目录
cd "${project_dir}"

# 指定输出文件目录不存在则创建
if [ -d "$export_path" ] ; then
    echo -e "$export_path"
else
    mkdir -pv "$export_path"
fi


# 编译前清理工程
xcodebuild clean -workspace "${workspace_name}.xcworkspace" \
                 -scheme "${scheme_name}" \
                 -configuration "${build_configuration}" | xcpretty -f `xcpretty-travis-formatter`

xcodebuild archive -workspace "${workspace_name}.xcworkspace" \
                   -scheme "${scheme_name}" \
                   -configuration "${build_configuration}" \
                   -archivePath "${export_archive_path}" | xcpretty -f `xcpretty-travis-formatter`

# 检查是否构建成功
# xcarchive 实际是一个文件夹不是一个文件所以使用 -d 判断
if [ -d "$export_archive_path" ] ; then
    echo -e "\033[32;1m项目构建成功 🚀 🚀 🚀  \033[0m"
else
    echo -e "\033[31;1m项目构建失败 😢 😢 😢  \033[0m"
    clean_temp
    exit 1
fi

# ===================================
# 导出 ipa 文件
echo -e "\033[32m开始导出ipa文件... \033[0m"

# 先删除export_options_plist文件
if [ -f "$export_options_plist_path" ] ; then
    # echo -e "${export_options_plist_path}文件存在，进行删除"
    rm -f "$export_options_plist_path"
fi
# 根据参数生成export_options_plist文件
/usr/libexec/PlistBuddy -c  "Add :method String ${method}"  "$export_options_plist_path"
/usr/libexec/PlistBuddy -c  "Add :signingStyle String automatic"  "$export_options_plist_path"
/usr/libexec/PlistBuddy -c  "Add :stripSwiftSymbols bool YES"  "$export_options_plist_path"
/usr/libexec/PlistBuddy -c  "Add :teamID String ${workspage_team_id}"  "$export_options_plist_path"
/usr/libexec/PlistBuddy -c  "Add :compileBitcode bool NO"  "$export_options_plist_path"

xcodebuild  -exportArchive \
            -archivePath "${export_archive_path}" \
            -exportPath "${export_ipa_path}" \
            -exportOptionsPlist "${export_options_plist_path}" \
            -allowProvisioningUpdates | xcpretty -f `xcpretty-travis-formatter`

# 检查ipa文件是否存在
if [ -f "$export_ipa_path/$scheme_name.ipa" ] ; then
    echo -e "\033[32;1mexportArchive ipa包成功,准备进行重命名\033[0m"
else
    echo -e "\033[31;1mexportArchive ipa包失败 😢 😢 😢     \033[0m"
    clean_temp
    exit 1
fi

# 修改ipa文件名称
mv "$export_ipa_path/$scheme_name.ipa" "$export_ipa_path/$ipa_name.ipa"

# 检查文件是否存在
if [ -f "$export_ipa_path/$ipa_name.ipa" ] ; then
    echo -e "\033[32;1m导出 ${ipa_name}.ipa 包成功 🎉  🎉  🎉   \033[0m"
    # open $export_path
else
    echo -e "\033[31;1m导出 ${ipa_name}.ipa 包失败 😢 😢 😢     \033[0m"
    clean_temp
    exit 1
fi

# 删除export_options_plist文件（中间文件）
if [ -f "$export_options_plist_path" ] ; then
    # echo -e "${export_options_plist_path}文件存在，准备删除"
    rm -f "$export_options_plist_path"
fi

# 导出dSYM并压缩 zip
cp -r "${dSYM_path}" "${export_path}"
zip -r "$zip_dSYM_path" "$new_dSYM_path"
rm -r "$new_dSYM_path"

# 输出打包总用时
echo -e "\033[36;1m使用AutoPackage打包总用时: ${SECONDS}s \033[0m"

if $is_upload_dSYM_Bugly ; then
    # 准备上传dSYM文件到 bugly
    echo -e "\033[33m准备上传dSYM文件到 Bugly... \033[0m"
    
    curl -k "https://api.bugly.qq.com/openapi/file/upload/symbol?app_key=$bugly_app_key&app_id=$bugly_app_id" \
    --form "api_version=1" --form "app_id=$bugly_app_id" --form "app_key=$bugly_app_key" \
    --form "symbolType=2" --form "bundleId=$workspage_bundle_id"  --form "fileName=$scheme_name.app.dSYM.zip" \
    --form "file=@/$zip_dSYM_path" --verbose | python -m json.tool
    echo -e "\033[33m上传dSYM文件到 Bugly 成功 \033[0m"
fi


# ===================================
# 上传 App Store
if [ $number == 1 ];then
echo -e "\033[33m准备上传ipa到App Store... \033[0m"
# 验证并上传到App Store，将-u 后面的XXX替换成自己的AppleID的账号，-p后面的XXX替换成自己的密码
altoolPath="$selected_xcode_path/Contents/Applications/Application Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Versions/A/Support/altool"
"$altoolPath" --validate-app -f "${ipa_name}.ipa" -u "$apple_id" -p "$apple_id_password" -t ios --output-format xml
"$altoolPath" --upload-app -f "${ipa_name}.ipa" -u  "$apple_id" -p "$apple_id_password" -t ios --output-format xml
echo -e "\033[33m上传ipa到App Store成功 \033[0m"
fi

# 恢复默认 xcode-select
if [[ `expr ${#xcode_paths[@]}` > 1 ]]; then
    echo -e "\033[32;1m恢复默认 xcode-select \033[0m"
    sudo xcode-select --reset
fi

# 打开输出目录
open "$export_path"
echo -e "\033[32;1m全部完成 🎉🎉🎉\033[0m"
exit 0