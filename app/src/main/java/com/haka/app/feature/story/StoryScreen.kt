package com.haka.app.feature.story

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.clip
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Circle
import androidx.compose.material.icons.rounded.DateRange
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.haka.app.core.model.*
import com.haka.app.data.heart.HakaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.net.Uri
import android.app.DatePickerDialog
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Calendar
import coil.compose.AsyncImage
import javax.inject.Inject

private val StoryTop = Color(0xFF080815); private val StoryBottom = Color(0xFF1A1022)
private val Ink = Color(0xFFF9F5FC); private val Soft = Color(0xFFBDB3C7); private val Accent = Color(0xFFFF5C91); private val Purple = Color(0xFF9B5CFF); private val Panel = Color(0xB31B1928)
private val StoryGradient = Brush.linearGradient(listOf(Color(0xFFFF5F8F), Color(0xFFE747A1), Purple))
data class StoryUiState(val data: StoryResponse = StoryResponse(), val loading: Boolean = true, val message: String? = null)

@HiltViewModel class StoryViewModel @Inject constructor(private val repository: HakaRepository) : ViewModel() {
    private val _state = MutableStateFlow(StoryUiState()); val state: StateFlow<StoryUiState> = _state
    fun load(coupleId: String) = viewModelScope.launch { runCatching { repository.getStory(coupleId) }.onSuccess { _state.value = StoryUiState(it, false) }.onFailure { _state.value = _state.value.copy(loading = false, message = "Could not load your shared story.") } }
    private fun update(work: suspend () -> StoryResponse) = viewModelScope.launch { runCatching { work() }.onSuccess { _state.value = StoryUiState(it, false, "Saved for both of you.") }.onFailure { _state.value = _state.value.copy(message = "Could not save that right now.") } }
    fun memory(c: String, t: String, x: String, d: String?, photos: List<String>) {
        if (!validOptionalDate(d)) { _state.value = _state.value.copy(message = "Please select a valid date."); return }
        update { repository.addMemory(c,t,x,d,photos) }
    }
    fun bucket(c: String, t: String) = update { repository.addBucketItem(c,t) }
    fun bucketList(c:String,t:String)=update{repository.addBucketList(c,t)}
    fun bucketListItem(c:String,listId:String,t:String)=update{repository.addBucketListItem(c,listId,t)}
    fun deleteBucketList(c:String,id:String)=viewModelScope.launch{runCatching{repository.deleteBucketList(c,id)}.onSuccess{_state.value=_state.value.copy(data=_state.value.data.copy(bucketLists=_state.value.data.bucketLists.filterNot{it.id==id},bucketItems=_state.value.data.bucketItems.filterNot{it.listId==id}),message="List deleted.")}.onFailure{_state.value=_state.value.copy(message="Could not delete that list.")}}
    fun editBucketList(c:String,id:String,title:String)=viewModelScope.launch{runCatching{repository.updateBucketList(c,id,title)}.onSuccess{_state.value=_state.value.copy(data=_state.value.data.copy(bucketLists=_state.value.data.bucketLists.map{if(it.id==id)it.copy(title=title)else it}),message="List updated.")}.onFailure{_state.value=_state.value.copy(message="Could not update that list.")}}
    fun toggle(c: String, id: String) = viewModelScope.launch {
        val before = _state.value.data.bucketItems
        val optimistic = before.map { if (it.id == id) it.copy(completedAt = if (it.completedAt == null) 1L else null) else it }
        _state.value = _state.value.copy(data = _state.value.data.copy(bucketItems = optimistic), message = null)
        runCatching { repository.toggleBucketItem(c,id) }.onFailure { _state.value = _state.value.copy(data = _state.value.data.copy(bucketItems = before), message = "Could not update that item.") }
    }
    fun deleteMemory(c: String, id: String) = viewModelScope.launch { runCatching { repository.deleteMemory(c,id) }.onSuccess { _state.value = _state.value.copy(data = _state.value.data.copy(memories = _state.value.data.memories.filterNot { it.id == id }), message = "Memory deleted.") }.onFailure { _state.value = _state.value.copy(message = "Could not delete that memory.") } }
    fun deleteBucket(c: String, id: String) = viewModelScope.launch { runCatching { repository.deleteBucketItem(c,id) }.onSuccess { _state.value = _state.value.copy(data = _state.value.data.copy(bucketItems = _state.value.data.bucketItems.filterNot { it.id == id }), message = "Bucket item deleted.") }.onFailure { _state.value = _state.value.copy(message = "Could not delete that item.") } }
    fun deleteDate(c: String, id: String) = viewModelScope.launch { runCatching { repository.deleteRelationshipDate(c,id) }.onSuccess { _state.value = _state.value.copy(data = _state.value.data.copy(dates = _state.value.data.dates.filterNot { it.id == id }), message = "Date deleted.") }.onFailure { _state.value = _state.value.copy(message = "Could not delete that date.") } }
    fun editBucket(c:String,id:String,title:String)=viewModelScope.launch{runCatching{repository.updateBucketItem(c,id,title)}.onSuccess{_state.value=_state.value.copy(data=_state.value.data.copy(bucketItems=_state.value.data.bucketItems.map{if(it.id==id)it.copy(title=title)else it}),message="Item updated.")}.onFailure{_state.value=_state.value.copy(message="Could not update that item.")}}
    fun editDate(c:String,d:RelationshipDateDto,label:String,kind:String,date:String,remind:Boolean) {
        if (!validDate(date) || kind !in setOf("anniversary","birthday","custom")) { _state.value=_state.value.copy(message="Please select a valid date.");return }
        viewModelScope.launch{runCatching{repository.updateRelationshipDate(c,d,label,kind,date,remind)}.onSuccess{_state.value=_state.value.copy(data=_state.value.data.copy(dates=_state.value.data.dates.map{if(it.id==d.id)it.copy(label=label,kind=kind,occursOn=date,remindAnnually=remind)else it}),message="Date updated.")}.onFailure{_state.value=_state.value.copy(message="Could not update that date.")}}
    }
    fun editMemory(c:String,m:MemoryDto,title:String,caption:String,date:String?,keys:List<String>,newPhotos:List<String>) {
        if (!validOptionalDate(date)) { _state.value=_state.value.copy(message="Please select a valid date.");return }
        viewModelScope.launch{runCatching{repository.updateMemory(c,m.copy(photoKeys=keys),title,caption,date,newPhotos)}.onSuccess{load(c);_state.value=_state.value.copy(message="Memory updated.")}.onFailure{_state.value=_state.value.copy(message="Could not update that memory.")}}
    }
    fun date(c: String, l: String, k: String, d: String, remind:Boolean) {
        if (!validDate(d) || k !in setOf("anniversary", "birthday", "custom")) { _state.value = _state.value.copy(message = "Please select a valid date."); return }
        update { repository.addRelationshipDate(c,l,k,d,remind) }
    }
}

@Composable fun StoryScreen(cached: CachedHakaState, viewModel: StoryViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState(); val coupleId = cached.coupleId
    LaunchedEffect(coupleId) { coupleId?.let(viewModel::load) }
    val snackbarHostState = remember { SnackbarHostState() }
    val uiScope = rememberCoroutineScope()
    LaunchedEffect(state.message) { state.message?.let { snackbarHostState.showSnackbar(it) } }
    var dialog by remember { mutableStateOf<String?>(null) }
    var selectedBucket by remember { mutableStateOf<BucketItemDto?>(null) }
    var editingBucket by remember { mutableStateOf<BucketItemDto?>(null) }
    var selectedDate by remember { mutableStateOf<RelationshipDateDto?>(null) }
    var editingDate by remember { mutableStateOf<RelationshipDateDto?>(null) }
    var selectedMemory by remember { mutableStateOf<MemoryDto?>(null) }
    var selectedList by remember { mutableStateOf<BucketListDto?>(null) }
    var editingList by remember { mutableStateOf<BucketListDto?>(null) }
    var editingMemory by remember { mutableStateOf<MemoryDto?>(null) }
    var destination by rememberSaveable { mutableStateOf("summary") }
    val context = LocalContext.current
    var memoryPhotos by remember { mutableStateOf<List<String>>(emptyList()) }
    var editPhotos by remember { mutableStateOf<List<String>>(emptyList()) };var pickingEdit by remember{mutableStateOf(false)}
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris -> val encoded=uris.mapNotNull{encodePhoto(context,it)};if(pickingEdit)editPhotos=(editPhotos+encoded).take(8) else memoryPhotos=(memoryPhotos+encoded).take(8);pickingEdit=false }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(StoryTop, StoryBottom)))) {
        when(destination) {
            "summary" -> StorySummary(state.data, { destination="memories" }, { destination="bucket" }, { destination="dates" })
            "memories" -> MemoriesPage(state.data.memories, { destination="summary" }, { dialog="memory" }, { selectedMemory=it }, { destination="allMemories" })
            "allMemories" -> AllMemoriesPage(state.data.memories, { destination="memories" }, { dialog="memory" }, { selectedMemory=it })
            "bucket" -> BucketPage(state.data, { destination="summary" }, { dialog="bucket" }, { selectedBucket=it }, { selectedList=it })
            "dates" -> DatesPage(state.data.dates, { destination="summary" }, { dialog="date" }, { selectedDate=it })
        }
        SnackbarHost(hostState = snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp))
    }
    when (dialog) {
        "memory" -> AddMemoryDialog(memoryPhotos,{photoPicker.launch("image/*")},{index->memoryPhotos=memoryPhotos.filterIndexed{i,_->i!=index}},{from,to->memoryPhotos=memoryPhotos.toMutableList().apply{add(to,removeAt(from))}},{dialog=null}) { t,x,d -> if(t.isBlank())uiScope.launch{snackbarHostState.showSnackbar("Please enter a memory title.")} else { coupleId?.let { viewModel.memory(it,t,x,d,memoryPhotos) };memoryPhotos=emptyList();dialog=null } }
        "bucket" -> AddBucketDialog({dialog=null},{t->if(t.isBlank())uiScope.launch{snackbarHostState.showSnackbar("Please enter an item title.")}else{coupleId?.let{viewModel.bucket(it,t)};dialog=null}}){t->if(t.isBlank())uiScope.launch{snackbarHostState.showSnackbar("Please enter a list title.")}else{coupleId?.let{viewModel.bucketList(it,t)};dialog=null}}
        "date" -> AddDateDialog({dialog=null},{uiScope.launch{snackbarHostState.showSnackbar("Please select a valid date.")}}) { l,k,d,r -> if(l.isBlank())uiScope.launch{snackbarHostState.showSnackbar("Please enter an event name.")}else{coupleId?.let{viewModel.date(it,l,k,d,r)};dialog=null} }
    }
    coupleId?.let { id ->
        selectedBucket?.let { item -> ItemSheet(item.title,"Bucket list item",{selectedBucket=null},{viewModel.toggle(id,item.id);selectedBucket=null},{editingBucket=item;selectedBucket=null},{viewModel.deleteBucket(id,item.id);selectedBucket=null}) }
        editingBucket?.let { item -> EditTextDialog("Edit bucket item",item.title,{editingBucket=null}) { viewModel.editBucket(id,item.id,it);editingBucket=null } }
        selectedDate?.let { item -> DateItemSheet(item,{selectedDate=null},{editingDate=item;selectedDate=null},{viewModel.deleteDate(id,item.id);selectedDate=null}) }
        editingDate?.let { item -> EditDateDialog(item,{editingDate=null}) { l,k,d,r->viewModel.editDate(id,item,l,k,d,r);editingDate=null } }
        selectedMemory?.let { item -> MemoryViewer(item,{selectedMemory=null},{editingMemory=item;selectedMemory=null},{viewModel.deleteMemory(id,item.id);selectedMemory=null}) }
        editingMemory?.let { item -> EditMemoryDialog(item,editPhotos,{pickingEdit=true;photoPicker.launch("image/*")},{index->editPhotos=editPhotos.filterIndexed{i,_->i!=index}},{editingMemory=null;editPhotos=emptyList()}) { title,caption,date,keys,newPhotos -> viewModel.editMemory(id,item,title,caption,date,keys,newPhotos);editingMemory=null;editPhotos=emptyList() } }
        selectedList?.let { list -> BucketListSheet(list,state.data.bucketItems.filter{it.listId==list.id},{selectedList=null},{editingList=list;selectedList=null},{title->viewModel.bucketListItem(id,list.id,title)},{item->selectedBucket=item;selectedList=null},{viewModel.deleteBucketList(id,list.id);selectedList=null}) }
        editingList?.let { list -> EditTextDialog("Edit bucket list",list.title,{editingList=null}){viewModel.editBucketList(id,list.id,it);editingList=null} }
    }
}
@Composable private fun StorySummary(data: StoryResponse, memories:()->Unit, bucket:()->Unit, dates:()->Unit) = Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(16.dp)) {
    Text("Our Story",color=Ink,style=MaterialTheme.typography.displaySmall,fontWeight=FontWeight.Bold); Text("A timeline of your moments, dreams and everything in between.",color=Soft)
    SummaryTile("Memories","${data.memories.size} memories",Icons.Rounded.PhotoLibrary,memories) { LazyRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) { items(data.memories.flatMap{it.photoPaths}.take(4)) { AsyncImage(model=it,contentDescription=null,modifier=Modifier.size(58.dp).background(Color.DarkGray,RoundedCornerShape(9.dp))) } } }
    data.memories.take(5).forEach { memory -> MemoryCard(memory,memories) }
    if(data.memories.size>5) TextButton(onClick=memories,modifier=Modifier.fillMaxWidth()){Text("Show all ${data.memories.size} memories",color=Accent)}
    SummaryTile("Bucket List","${data.bucketLists.size} lists • ${data.bucketItems.count{it.listId==null}} single items",Icons.Rounded.CheckCircle,bucket) { data.bucketItems.take(2).forEach { Text((if(it.completedAt!=null) "✓ " else "○ ")+it.title,color=Soft) } }
    SummaryTile("Important Dates","${data.dates.size} dates",Icons.Rounded.DateRange,dates) { data.dates.take(2).forEach { Text("${it.label}  •  ${it.occursOn}",color=Soft) } }
}
@Composable private fun SummaryTile(title:String,subtitle:String,icon:androidx.compose.ui.graphics.vector.ImageVector,click:()->Unit,preview:@Composable ColumnScope.()->Unit) = Column(Modifier.fillMaxWidth().clickable(onClick=click).background(Panel,RoundedCornerShape(20.dp)).border(1.dp,Color(0x33FFFFFF),RoundedCornerShape(20.dp)).padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) { Row(verticalAlignment=Alignment.CenterVertically) { Icon(icon,null,tint=Accent); Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)){Text(title,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleLarge);Text(subtitle,color=Soft,style=MaterialTheme.typography.labelMedium)};Icon(Icons.Rounded.ChevronRight,null,tint=Soft) };preview() }
@Composable private fun PageHeader(title:String,back:()->Unit,add:()->Unit) = Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
    IconButton(onClick=back){Icon(Icons.Rounded.ArrowBack,"Back",tint=Ink)}
    Text(title,color=Ink,style=MaterialTheme.typography.headlineMedium,fontWeight=FontWeight.Bold)
    Text("♡",color=Accent,style=MaterialTheme.typography.headlineMedium,modifier=Modifier.padding(start=6.dp).weight(1f))
    Box(Modifier.size(46.dp).clip(CircleShape).background(StoryGradient).clickable(onClick=add),contentAlignment=Alignment.Center){Icon(Icons.Rounded.Add,"Add",tint=Color.White)}
}

@Composable private fun MemoriesPage(items:List<MemoryDto>,back:()->Unit,add:()->Unit,open:(MemoryDto)->Unit,showAll:()->Unit) = LazyColumn(
    Modifier.fillMaxSize().padding(horizontal=16.dp).navigationBarsPadding(),
    contentPadding=PaddingValues(top=14.dp,bottom=24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)
) {
    item { PageHeader("Memories",back,add); Spacer(Modifier.height(18.dp)); Text("Your memories",color=Ink,fontWeight=FontWeight.SemiBold);Text("Moments we’ll always cherish.",color=Soft) }
    if(items.isEmpty()) item { Empty("No memories yet. Add a moment you want to keep forever.") }
    items(items.take(5),key={it.id}) { memory -> PremiumMemoryCard(memory){open(memory)} }
    if(items.isNotEmpty()) item { GradientOutlineButton(if(items.size>5) "Show all ${items.size} memories" else "Browse all memories",showAll) }
}

@Composable private fun AllMemoriesPage(items:List<MemoryDto>,back:()->Unit,add:()->Unit,open:(MemoryDto)->Unit) {
    var year by rememberSaveable { mutableStateOf("All") }
    val years=remember(items){listOf("All")+items.mapNotNull{it.occurredOn?.take(4)}.distinct().sortedDescending()}
    val filtered=if(year=="All")items else items.filter{it.occurredOn?.startsWith(year)==true}
    LazyVerticalGrid(columns=GridCells.Fixed(2),modifier=Modifier.fillMaxSize().padding(horizontal=16.dp).navigationBarsPadding(),contentPadding=PaddingValues(top=14.dp,bottom=24.dp),horizontalArrangement=Arrangement.spacedBy(10.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        item(span={androidx.compose.foundation.lazy.grid.GridItemSpan(2)}) { Column { PageHeader("All Memories",back,add);Spacer(Modifier.height(12.dp));LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp)){items(years){value->RomanticChip(value,year==value){year=value}}};Spacer(Modifier.height(6.dp)) } }
        if(filtered.isEmpty()) item(span={androidx.compose.foundation.lazy.grid.GridItemSpan(2)}){Empty("No memories in this collection.")}
        gridItems(filtered,key={it.id}){memory->Column(Modifier.clip(RoundedCornerShape(16.dp)).background(Panel).border(1.dp,Color(0x28FF6FA3),RoundedCornerShape(16.dp)).clickable{open(memory)}.padding(8.dp)){AsyncImage(memory.photoPaths.firstOrNull(),null,Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(11.dp)).background(Color(0xFF282334)),contentScale=ContentScale.Crop);Spacer(Modifier.height(8.dp));Text(memory.title,color=Ink,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis);Text(prettyDate(memory.occurredOn),color=Soft,style=MaterialTheme.typography.labelSmall)}}
    }
}

@Composable private fun BucketPage(data:StoryResponse,back:()->Unit,add:()->Unit,open:(BucketItemDto)->Unit,openList:(BucketListDto)->Unit) {
    var tab by rememberSaveable{mutableStateOf("My Lists")};val singles=data.bucketItems.filter{it.listId==null}
    LazyColumn(Modifier.fillMaxSize().padding(horizontal=16.dp).navigationBarsPadding(),contentPadding=PaddingValues(top=14.dp,bottom=24.dp),verticalArrangement=Arrangement.spacedBy(10.dp)){
        item{PageHeader("Bucket List",back,add);Spacer(Modifier.height(18.dp));Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){RomanticChip("My Lists",tab=="My Lists"){tab="My Lists"};RomanticChip("Single Items",tab=="Single Items"){tab="Single Items"}};Spacer(Modifier.height(10.dp));Text(if(tab=="My Lists")"Our Lists" else "Little dreams together",color=Ink,style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)}
        if(tab=="My Lists") {
            if(data.bucketLists.isEmpty())item{Empty("Create your first shared list.")}
            items(data.bucketLists,key={it.id}){list->val children=data.bucketItems.filter{it.listId==list.id};BucketGroupCard(list,children){openList(list)}}
        } else {
            if(singles.isEmpty())item{Empty("Add a standalone dream for the two of you.")}
            items(singles,key={it.id}){item->BucketRow(item){open(item)}}
        }
    }
}

@Composable private fun DatesPage(items:List<RelationshipDateDto>,back:()->Unit,add:()->Unit,open:(RelationshipDateDto)->Unit) {
    var filter by rememberSaveable{mutableStateOf("All")};val choices=listOf("All","Anniversaries","Birthdays","Custom");val visible=items.filter{filter=="All"||when(filter){"Anniversaries"->it.kind=="anniversary";"Birthdays"->it.kind=="birthday";else->it.kind=="custom"}}
    LazyColumn(Modifier.fillMaxSize().padding(horizontal=16.dp).navigationBarsPadding(),contentPadding=PaddingValues(top=14.dp,bottom=24.dp),verticalArrangement=Arrangement.spacedBy(10.dp)){
        item{PageHeader("Important Dates",back,add);Spacer(Modifier.height(18.dp));LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp)){items(choices){choice->RomanticChip(choice,filter==choice){filter=choice}}};Spacer(Modifier.height(8.dp))}
        if(visible.isEmpty())item{Empty("No meaningful dates here yet.")}
        items(visible,key={it.id}){date->ImportantDateCard(date){open(date)}}
        if(items.isNotEmpty())item{ReminderCallout()}
    }
}
@Composable private fun SectionHeader(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, add: () -> Unit) = Row(Modifier.fillMaxWidth().padding(top=8.dp), verticalAlignment=Alignment.CenterVertically) { Icon(icon,null,tint=Accent); Spacer(Modifier.width(8.dp)); Text(title,color=Ink,style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold,modifier=Modifier.weight(1f)); IconButton(onClick=add) { Icon(Icons.Rounded.Add,"Add $title",tint=Accent) } }
@Composable private fun StoryCard(title: String, detail: String, date: String?, click: () -> Unit = {}) = Column(Modifier.fillMaxWidth().clickable(onClick=click).background(Panel,RoundedCornerShape(18.dp)).border(1.dp,Color(0x33FFFFFF),RoundedCornerShape(18.dp)).padding(16.dp)) { Text(title,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium); Spacer(Modifier.height(4.dp)); Text(detail,color=Soft); date?.let { Text(it,color=Accent,style=MaterialTheme.typography.labelMedium,modifier=Modifier.padding(top=8.dp)) } }
@Composable private fun RomanticChip(label:String,selected:Boolean,onClick:()->Unit)=Surface(onClick=onClick,shape=RoundedCornerShape(50),color=Color.Transparent,border=if(selected)null else androidx.compose.foundation.BorderStroke(1.dp,Color(0x2EFFFFFF))){Box(Modifier.background(if(selected)StoryGradient else Brush.linearGradient(listOf(Color.Transparent,Color.Transparent))).padding(horizontal=20.dp,vertical=9.dp)){Text(label,color=if(selected)Color.White else Soft,style=MaterialTheme.typography.labelLarge)}}

@Composable private fun GradientOutlineButton(label:String,onClick:()->Unit)=Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(StoryGradient).padding(1.dp).clip(RoundedCornerShape(21.dp)).background(Color(0xFF171321)).clickable(onClick=onClick).padding(vertical=14.dp),contentAlignment=Alignment.Center){Text("$label  ›",color=Accent,fontWeight=FontWeight.SemiBold)}

@Composable private fun PremiumMemoryCard(memory:MemoryDto,click:()->Unit)=Row(Modifier.fillMaxWidth().heightIn(min=132.dp).clip(RoundedCornerShape(18.dp)).background(Panel).border(1.dp,Color(0x2BFF72A6),RoundedCornerShape(18.dp)).clickable(onClick=click)){
    Box(Modifier.width(150.dp).fillMaxHeight().heightIn(min=132.dp)){
        if(memory.photoPaths.isEmpty())Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF34233F),Color(0xFF171524)))),contentAlignment=Alignment.Center){Icon(Icons.Rounded.PhotoLibrary,null,tint=Accent)}
        else { val pager=rememberPagerState{memory.photoPaths.size};HorizontalPager(pager,Modifier.fillMaxSize()){page->AsyncImage(memory.photoPaths[page],"Photo ${page+1} for ${memory.title}",Modifier.fillMaxSize(),contentScale=ContentScale.Crop)};Surface(color=Color(0xB3000000),shape=RoundedCornerShape(8.dp),modifier=Modifier.align(Alignment.BottomStart).padding(8.dp)){Text("▣ ${memory.photoPaths.size}",color=Color.White,style=MaterialTheme.typography.labelSmall,modifier=Modifier.padding(horizontal=7.dp,vertical=3.dp))}}
    }
    Column(Modifier.weight(1f).padding(14.dp)){Row(verticalAlignment=Alignment.CenterVertically){Text(memory.title,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium,maxLines=1,overflow=TextOverflow.Ellipsis,modifier=Modifier.weight(1f));Text("♥",color=Accent);Text("⋮",color=Soft,style=MaterialTheme.typography.titleLarge,modifier=Modifier.padding(start=8.dp))};Text(prettyDate(memory.occurredOn),color=Soft,style=MaterialTheme.typography.labelMedium,modifier=Modifier.padding(top=3.dp));if(memory.caption.isNotBlank())Text(memory.caption,color=Soft,maxLines=3,overflow=TextOverflow.Ellipsis,modifier=Modifier.padding(top=9.dp))}
}

@Composable private fun BucketGroupCard(list:BucketListDto,items:List<BucketItemDto>,click:()->Unit){val done=items.count{it.completedAt!=null};Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).border(1.dp,Color(0x28FF72A6),RoundedCornerShape(18.dp)).clickable(onClick=click).padding(16.dp)){Row(verticalAlignment=Alignment.CenterVertically){Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(StoryGradient),contentAlignment=Alignment.Center){Text("♥",color=Color.White)};Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(list.title,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium);Text("${items.size} items  •  $done completed",color=Soft,style=MaterialTheme.typography.labelMedium)};Icon(Icons.Rounded.ChevronRight,null,tint=Ink)};if(items.isNotEmpty()){Spacer(Modifier.height(12.dp));LinearProgressIndicator(progress={done.toFloat()/items.size},modifier=Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),color=Accent,trackColor=Color(0x22FFFFFF))}}}

@Composable private fun ImportantDateCard(item:RelationshipDateDto,click:()->Unit){val emoji=when(item.kind){"anniversary"->"♥";"birthday"->"🎁";else->"▣"};val status=relativeDate(item.occursOn,item.remindAnnually);Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).border(1.dp,Color(0x28FF72A6),RoundedCornerShape(18.dp)).clickable(onClick=click).padding(14.dp),verticalAlignment=Alignment.CenterVertically){Box(Modifier.size(48.dp).clip(CircleShape).background(Brush.linearGradient(listOf(Accent.copy(alpha=.55f),Purple.copy(alpha=.35f)))),contentAlignment=Alignment.Center){Text(emoji,color=Color.White,style=MaterialTheme.typography.titleLarge)};Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(item.label,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium);Text(prettyDate(item.occursOn),color=Soft,style=MaterialTheme.typography.labelMedium);Text(item.kind.replaceFirstChar(Char::uppercase),color=Soft,style=MaterialTheme.typography.labelSmall)};Text(status,color=if(status=="Passed")Color(0xFF55DCA3) else Accent,fontWeight=FontWeight.SemiBold)}
}

@Composable private fun ReminderCallout()=Row(Modifier.fillMaxWidth().padding(top=12.dp).clip(RoundedCornerShape(18.dp)).background(Brush.linearGradient(listOf(Color(0x33251A2D),Color(0x33421836)))).border(1.dp,Accent.copy(alpha=.6f),RoundedCornerShape(18.dp)).padding(16.dp),verticalAlignment=Alignment.Top){Text("💕",style=MaterialTheme.typography.headlineSmall);Spacer(Modifier.width(12.dp));Column{Text("Never miss an important day",color=Accent,fontWeight=FontWeight.Bold);Text("We’ll remind you before every special date.",color=Soft)}}

private fun prettyDate(value:String?):String { if(value.isNullOrBlank())return "No date";return runCatching{LocalDate.parse(value).format(DateTimeFormatter.ofPattern("dd MMM yyyy"))}.getOrElse{"Date unavailable"} }
private fun relativeDate(value:String,annual:Boolean):String=runCatching{val original=LocalDate.parse(value);val today=LocalDate.now();val target=if(annual){var next=original.withYear(today.year);if(next.isBefore(today))next=next.plusYears(1);next}else original;val days=ChronoUnit.DAYS.between(today,target);when{!annual&&days<0->"Passed";days==0L->"Today";else->"In $days days"}}.getOrElse{"Unavailable"}
@Composable private fun MemoryCard(memory: MemoryDto, click: () -> Unit) = Column(Modifier.fillMaxWidth().clickable(onClick=click).background(Panel,RoundedCornerShape(18.dp)).border(1.dp,Color(0x33FFFFFF),RoundedCornerShape(18.dp)).padding(16.dp)) { if(memory.photoPaths.isNotEmpty()) { LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp),modifier=Modifier.fillMaxWidth()) { items(memory.photoPaths.take(5)) { photo -> AsyncImage(model=photo, contentDescription="Photo for ${memory.title}", modifier=Modifier.width(250.dp).height(180.dp).background(Color(0x22111111),RoundedCornerShape(12.dp))) } };if(memory.photoPaths.size>5)Text("View all ${memory.photoPaths.size} photos",color=Accent,style=MaterialTheme.typography.labelMedium,modifier=Modifier.padding(top=6.dp));Spacer(Modifier.height(12.dp)) }; Text(memory.title,color=Ink,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium); if(memory.caption.isNotBlank()) { Spacer(Modifier.height(4.dp)); Text(memory.caption,color=Soft) }; memory.occurredOn?.let { Text(it,color=Accent,style=MaterialTheme.typography.labelMedium,modifier=Modifier.padding(top=8.dp)) } }
@Composable private fun BucketRow(item: BucketItemDto, toggle: () -> Unit) = Row(Modifier.fillMaxWidth().clickable(onClick=toggle).background(Panel,RoundedCornerShape(18.dp)).padding(16.dp),verticalAlignment=Alignment.CenterVertically) { Icon(if(item.completedAt==null) Icons.Rounded.Circle else Icons.Rounded.CheckCircle,null,tint=if(item.completedAt==null) Soft else Accent); Spacer(Modifier.width(12.dp)); Text(item.title,color=if(item.completedAt==null) Ink else Soft,style=MaterialTheme.typography.titleMedium) }
@Composable private fun Empty(text: String) = Text(text,color=Soft,modifier=Modifier.fillMaxWidth().background(Panel,RoundedCornerShape(18.dp)).padding(16.dp))
@Composable private fun MemoryViewer(memory:MemoryDto,close:()->Unit,edit:()->Unit,delete:()->Unit) { var confirm by remember{mutableStateOf(false)}; val pager=rememberPagerState{maxOf(1,memory.photoPaths.size)}; Dialog(onDismissRequest=close,properties=DialogProperties(usePlatformDefaultWidth=false)) { Box(Modifier.fillMaxSize().background(StoryTop)) { Column(Modifier.fillMaxSize()) { Row(Modifier.fillMaxWidth().statusBarsPadding().padding(8.dp),verticalAlignment=Alignment.CenterVertically){IconButton(onClick=close){Icon(Icons.Rounded.ArrowBack,"Close",tint=Ink)};Text("${pager.currentPage+1} / ${maxOf(1,memory.photoPaths.size)}",color=Ink,modifier=Modifier.weight(1f),textAlign=androidx.compose.ui.text.style.TextAlign.Center);IconButton(onClick=edit){Icon(Icons.Rounded.Edit,"Edit",tint=Ink)};IconButton(onClick={confirm=true}){Icon(Icons.Rounded.Delete,"Delete",tint=Accent)}}; if(memory.photoPaths.isNotEmpty()) HorizontalPager(state=pager,modifier=Modifier.weight(1f)) { page -> AsyncImage(model=memory.photoPaths[page],contentDescription=null,modifier=Modifier.fillMaxSize()) } else Spacer(Modifier.weight(1f));Column(Modifier.padding(20.dp).navigationBarsPadding()){Text(memory.title,color=Ink,style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold);memory.occurredOn?.let{Text(it,color=Soft)};if(memory.caption.isNotBlank())Text(memory.caption,color=Ink,modifier=Modifier.padding(top=12.dp))} } };if(confirm)AlertDialog(onDismissRequest={confirm=false},title={Text("Delete memory?")},text={Text("This memory will be permanently removed.")},confirmButton={TextButton(onClick={confirm=false;delete()}){Text("Delete",color=Accent)}},dismissButton={TextButton(onClick={confirm=false}){Text("Cancel")}}) } }
@Composable
private fun EditMemoryDialog(memory:MemoryDto,newPhotos:List<String>,pick:()->Unit,removeNew:(Int)->Unit,dismiss:()->Unit,save:(String,String,String?,List<String>,List<String>)->Unit) {
    var title by remember { mutableStateOf(memory.title) }
    var caption by remember { mutableStateOf(memory.caption) }
    var date by remember { mutableStateOf(memory.occurredOn) }
    var pairs by remember { mutableStateOf(memory.photoKeys.zip(memory.photoPaths)) }
    StoryDialog("Edit memory",dismiss,{save(title,caption,date,pairs.map { it.first },newPhotos)}) {
        Field(title,{title=it},"Title")
        Field(caption,{caption=it},"Caption (optional)")
        DateField(date,{date=it},"Date (optional)")
        if (pairs.isNotEmpty()) LazyRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            items(pairs.size) { index ->
                Column(horizontalAlignment=Alignment.CenterHorizontally) {
                    AsyncImage(model=pairs[index].second,contentDescription=null,modifier=Modifier.size(72.dp).background(Color.DarkGray,RoundedCornerShape(8.dp)))
                    Row {
                        TextButton(enabled=index>0,onClick={pairs=pairs.toMutableList().apply{add(index-1,removeAt(index))}},contentPadding=PaddingValues(2.dp)){Text("‹")}
                        TextButton(onClick={pairs=pairs.filterIndexed{i,_->i!=index}},contentPadding=PaddingValues(2.dp)){Text("×",color=Accent)}
                        TextButton(enabled=index<pairs.lastIndex,onClick={pairs=pairs.toMutableList().apply{add(index+1,removeAt(index))}},contentPadding=PaddingValues(2.dp)){Text("›")}
                    }
                }
            }
        }
        if(newPhotos.isNotEmpty())LazyRow(horizontalArrangement=Arrangement.spacedBy(6.dp)){items(newPhotos.size){index->Column(horizontalAlignment=Alignment.CenterHorizontally){AsyncImage(model="data:image/jpeg;base64,${newPhotos[index]}",contentDescription=null,modifier=Modifier.size(72.dp));TextButton(onClick={removeNew(index)}){Text("Remove",color=Accent,style=MaterialTheme.typography.labelSmall)}}}}
        TextButton(onClick=pick,enabled=pairs.size+newPhotos.size<8){Text("Add images",color=Accent)}
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun BucketListSheet(list:BucketListDto,items:List<BucketItemDto>,close:()->Unit,edit:()->Unit,add:(String)->Unit,toggle:(BucketItemDto)->Unit,delete:()->Unit){var text by remember{mutableStateOf("")};var confirm by remember{mutableStateOf(false)};ModalBottomSheet(onDismissRequest=close){Column(Modifier.fillMaxWidth().padding(20.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(10.dp)){Row(verticalAlignment=Alignment.CenterVertically){Text(list.title,style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold,modifier=Modifier.weight(1f));IconButton(onClick=edit){Icon(Icons.Rounded.Edit,"Edit list")}};items.forEach{item->BucketRow(item){toggle(item)}};Row(verticalAlignment=Alignment.CenterVertically){OutlinedTextField(text,{text=it},label={Text("Add item")},modifier=Modifier.weight(1f));IconButton(enabled=text.isNotBlank(),onClick={add(text);text=""}){Icon(Icons.Rounded.Add,null)}};TextButton(onClick={confirm=true}){Text("Delete list",color=Accent)}}};if(confirm)AlertDialog(onDismissRequest={confirm=false},title={Text("Delete list?")},text={Text("All items inside it will also be deleted.")},confirmButton={TextButton(onClick={confirm=false;delete()}){Text("Delete",color=Accent)}},dismissButton={TextButton(onClick={confirm=false}){Text("Cancel")}})}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun DateItemSheet(item:RelationshipDateDto,close:()->Unit,edit:()->Unit,delete:()->Unit){var confirm by remember{mutableStateOf(false)};ModalBottomSheet(onDismissRequest=close){Column(Modifier.fillMaxWidth().padding(24.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(12.dp)){Text(item.label,style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold);Text("${item.kind.replaceFirstChar(Char::uppercase)} • ${item.occursOn}",color=Soft);Text(if(item.remindAnnually)"Annual reminder on" else "Reminder off",color=Accent);Button(onClick=edit,modifier=Modifier.fillMaxWidth()){Icon(Icons.Rounded.Edit,null);Spacer(Modifier.width(8.dp));Text("Edit")};TextButton(onClick={confirm=true},modifier=Modifier.fillMaxWidth()){Text("Delete",color=Accent)}}};if(confirm)AlertDialog(onDismissRequest={confirm=false},title={Text("Delete important date?")},confirmButton={TextButton(onClick={confirm=false;delete()}){Text("Delete",color=Accent)}},dismissButton={TextButton(onClick={confirm=false}){Text("Cancel")}})}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ItemSheet(title:String,detail:String,close:()->Unit,toggle:(()->Unit)?,edit:()->Unit,delete:()->Unit) {
    var confirm by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest=close) { Column(Modifier.fillMaxWidth().padding(24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text(title,style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold); Text(detail,color=Soft)
        toggle?.let { TextButton(onClick=it,modifier=Modifier.fillMaxWidth()) { Text("Check / uncheck",color=Accent) } }
        TextButton(onClick=edit,modifier=Modifier.fillMaxWidth()) { Icon(Icons.Rounded.Edit,null);Spacer(Modifier.width(8.dp));Text("Edit") }
        TextButton(onClick={confirm=true},modifier=Modifier.fillMaxWidth()) { Icon(Icons.Rounded.Delete,null); Spacer(Modifier.width(8.dp)); Text("Delete",color=Color(0xFFFF6B7A)) }
    } }
    if(confirm) AlertDialog(onDismissRequest={confirm=false},title={Text("Delete this item?")},text={Text("This cannot be undone.")},confirmButton={TextButton(onClick={confirm=false;delete()}){Text("Delete",color=Color(0xFFFF6B7A))}},dismissButton={TextButton(onClick={confirm=false}){Text("Cancel")}})
}
@Composable private fun EditTextDialog(title:String,initial:String,dismiss:()->Unit,save:(String)->Unit){var value by remember{mutableStateOf(initial)};StoryDialog(title,dismiss,{if(value.isNotBlank())save(value.trim())}){Field(value,{value=it},"Title")}}
@Composable
private fun AddMemoryDialog(photos:List<String>,pick:()->Unit,remove:(Int)->Unit,move:(Int,Int)->Unit,dismiss:()->Unit,save:(String,String,String?)->Unit) {
    var title by remember { mutableStateOf("") }; var caption by remember { mutableStateOf("") }; var date by remember { mutableStateOf<String?>(null) }
    StoryDialog("New memory",dismiss,{save(title,caption,date)}) {
        Field(title,{title=it},"Title"); Field(caption,{caption=it},"Caption (optional)"); DateField(date,{date=it},"Date (optional)")
        if (photos.isNotEmpty()) LazyRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            items(photos.size) { index ->
                Column(horizontalAlignment=Alignment.CenterHorizontally) {
                    AsyncImage(model="data:image/jpeg;base64,${photos[index]}",contentDescription="Selected photo",modifier=Modifier.size(72.dp).background(Color.DarkGray,RoundedCornerShape(8.dp)))
                    Row {
                        TextButton(enabled=index>0,onClick={move(index,index-1)},contentPadding=PaddingValues(2.dp)){Text("‹")}
                        TextButton(onClick={remove(index)},contentPadding=PaddingValues(2.dp)){Text("×",color=Accent)}
                        TextButton(enabled=index<photos.lastIndex,onClick={move(index,index+1)},contentPadding=PaddingValues(2.dp)){Text("›")}
                    }
                }
            }
        }
        TextButton(onClick=pick,enabled=photos.size<8){Text(if(photos.isNotEmpty())"Add more photos (${photos.size}/8)" else "Add photos",color=Accent)}
    }
}
@Composable private fun AddBucketDialog(dismiss:()->Unit,saveItem:(String)->Unit,saveList:(String)->Unit) { var t by remember{mutableStateOf("")};var group by remember{mutableStateOf(false)};StoryDialog(if(group)"New titled list" else "New standalone item",dismiss,{if(group)saveList(t) else saveItem(t)}) { Row(verticalAlignment=Alignment.CenterVertically){Text("Titled list",modifier=Modifier.weight(1f));Switch(group,{group=it})};Field(t,{t=it},if(group)"List title" else "Something to do together") } }
@Composable private fun AddDateDialog(dismiss:()->Unit,invalid:()->Unit,save:(String,String,String,Boolean)->Unit){var l by remember{mutableStateOf("")};var k by remember{mutableStateOf("anniversary")};var d by remember{mutableStateOf<String?>(null)};var r by remember{mutableStateOf(true)};StoryDialog("Important date",dismiss,{if(d==null)invalid()else save(l,k,d!!,r)}){Field(l,{l=it},"Label");KindPicker(k){k=it};DateField(d,{d=it},"Date");Row(verticalAlignment=Alignment.CenterVertically){Text("Annual reminder",modifier=Modifier.weight(1f));Switch(r,{r=it})}}}
@Composable private fun EditDateDialog(item:RelationshipDateDto,dismiss:()->Unit,save:(String,String,String,Boolean)->Unit){var l by remember{mutableStateOf(item.label)};var k by remember{mutableStateOf(item.kind)};var d by remember{mutableStateOf(item.occursOn)};var r by remember{mutableStateOf(item.remindAnnually)};StoryDialog("Edit important date",dismiss,{save(l,k,d,r)}){Field(l,{l=it},"Label");KindPicker(k){k=it};DateField(d,{d=it},"Date");Row(verticalAlignment=Alignment.CenterVertically){Text("Annual reminder",modifier=Modifier.weight(1f));Switch(r,{r=it})}}}
@Composable private fun KindPicker(value:String,change:(String)->Unit)=Row(horizontalArrangement=Arrangement.spacedBy(4.dp)){listOf("anniversary","birthday","custom").forEach{FilterChip(selected=value==it,onClick={change(it)},label={Text(it.replaceFirstChar(Char::uppercase),style=MaterialTheme.typography.labelSmall)})}}
@Composable private fun StoryDialog(title:String,dismiss:()->Unit,save:()->Unit,content:@Composable ColumnScope.()->Unit) = AlertDialog(onDismissRequest=dismiss,title={Text(title)},text={Column(content=content)},confirmButton={TextButton(onClick=save){Text("Save",color=Accent)}},dismissButton={TextButton(onClick=dismiss){Text("Cancel")}})
@Composable private fun Field(value:String, change:(String)->Unit, hint:String) = OutlinedTextField(value=value,onValueChange=change,label={Text(hint)},modifier=Modifier.fillMaxWidth().padding(vertical=4.dp),singleLine=true)
@Composable private fun DateField(value: String?, change: (String) -> Unit, hint: String) {
    val context=LocalContext.current
    val openPicker = {
        val initial=runCatching{value?.let(LocalDate::parse)}.getOrNull() ?: LocalDate.now()
        DatePickerDialog(context,{_,year,month,day->change(LocalDate.of(year,month+1,day).toString())},initial.year,initial.monthValue-1,initial.dayOfMonth).show()
    }
    Box(Modifier.fillMaxWidth().padding(vertical=4.dp)) {
        OutlinedTextField(value=if(value.isNullOrBlank())"" else prettyDate(value),onValueChange={},enabled=false,label={Text(hint)},trailingIcon={Icon(Icons.Rounded.DateRange,"Select date",tint=Accent)},colors=OutlinedTextFieldDefaults.colors(disabledTextColor=Ink,disabledLabelColor=Soft,disabledBorderColor=Color(0x44FFFFFF),disabledTrailingIconColor=Accent),modifier=Modifier.fillMaxWidth())
        Box(Modifier.matchParentSize().clip(RoundedCornerShape(4.dp)).clickable(onClick=openPicker))
    }
}
private fun validDate(value:String):Boolean=runCatching{LocalDate.parse(value)}.isSuccess
private fun validOptionalDate(value:String?):Boolean=value.isNullOrBlank()||validDate(value)
private fun encodePhoto(context: android.content.Context, uri: Uri): String? = runCatching {
    val source = context.contentResolver.openInputStream(uri) ?: return null
    val bitmap = source.use { BitmapFactory.decodeStream(it) } ?: return null
    val scale = minOf(1f, 1440f / maxOf(bitmap.width, bitmap.height).toFloat())
    val resized = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
    val output = ByteArrayOutputStream(); resized.compress(Bitmap.CompressFormat.JPEG, 82, output)
    Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
}.getOrNull()
